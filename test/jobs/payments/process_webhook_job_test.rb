require "test_helper"

module Payments
  class ProcessWebhookJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    CHECK_URL = "#{InfinitePay::Api::BASE_URL}/payment_check".freeze

    def order
      @order ||= Order.create!(user: users(:confirmed), subtotal_cents: 18_000, total_cents: 19_984)
    end

    def store_event(overrides = {})
      order.payment_webhook_events.create!(headers: {}, payload: {
        "order_nsu" => order.number, "paid_amount" => order.total_cents,
        "transaction_nsu" => "tx-1", "invoice_slug" => "slug-1",
        "receipt_url" => "https://recibo/tx", "capture_method" => "pix"
      }.merge(overrides))
    end

    def stub_check(overrides = {})
      body = { "success" => true, "paid" => true, "paid_amount" => order.total_cents, "capture_method" => "pix" }
      stub_request(:post, CHECK_URL).to_return(
        status: 200, body: body.merge(overrides).to_json, headers: { "Content-Type" => "application/json" }
      )
    end

    test "confirms the order once infinitepay vouches for the payment" do
      stub_check
      event = store_event

      Payments::ProcessWebhookJob.perform_now(event.id)

      assert order.reload.payment_confirmed?
      assert_equal "tx-1", order.external_id
      assert_equal "slug-1", order.invoice_slug
    end

    test "re-checks later while infinitepay still reports the transaction unpaid" do
      stub_check("paid" => false)
      event = store_event

      freeze_time do
        assert_enqueued_with(job: Payments::ProcessWebhookJob, args: [ event.id, 2 ], at: 30.seconds.from_now) do
          Payments::ProcessWebhookJob.perform_now(event.id)
        end
      end

      assert order.reload.awaiting_payment?
    end

    test "backs off between re-checks" do
      stub_check("paid" => false)
      event = store_event

      freeze_time do
        { 2 => 60.seconds, 3 => 120.seconds }.each do |attempt, delay|
          assert_enqueued_with(job: Payments::ProcessWebhookJob, args: [ event.id, attempt + 1 ], at: delay.from_now) do
            Payments::ProcessWebhookJob.perform_now(event.id, attempt)
          end
        end
      end
    end

    test "gives up after the last attempt instead of re-checking forever" do
      stub_check("paid" => false)
      event = store_event

      assert_no_enqueued_jobs do
        Payments::ProcessWebhookJob.perform_now(event.id, Payments::VERIFY_MAX_ATTEMPTS)
      end

      assert order.reload.awaiting_payment?
    end

    test "a delivery rejected on its own contents is never re-checked" do
      event = store_event("invoice_slug" => nil)

      assert_no_enqueued_jobs do
        Payments::ProcessWebhookJob.perform_now(event.id)
      end

      assert order.reload.awaiting_payment?
    end

    test "retries the whole job when infinitepay cannot be reached" do
      stub_request(:post, CHECK_URL).to_return(status: 503, body: "down")
      event = store_event

      assert_enqueued_jobs 1, only: Payments::ProcessWebhookJob do
        Payments::ProcessWebhookJob.perform_now(event.id)
      end

      assert order.reload.awaiting_payment?
    end

    test "is a no-op when the event was already purged" do
      assert_nothing_raised { Payments::ProcessWebhookJob.perform_now(-1) }
    end
  end
end
