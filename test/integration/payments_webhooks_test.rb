require "test_helper"

class PaymentsWebhooksTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  CHECK_URL = "#{InfinitePay::Api::BASE_URL}/payment_check".freeze

  setup do
    @order = Order.create!(
      user: users(:confirmed),
      subtotal_cents: 18_000, total_cents: 19_984,
    )
    stub_payment_check
  end

  def webhook(token, body)
    post payments_webhook_path(token), params: body.to_json, headers: { "Content-Type" => "application/json" }
  end

  def paid_payload(overrides = {})
    {
      "order_nsu" => @order.number, "paid_amount" => @order.total_cents,
      "transaction_nsu" => "tx-#{SecureRandom.hex(6)}", "invoice_slug" => "uXnT2kndIV",
      "receipt_url" => "https://recibo.infinitepay.io/tx", "capture_method" => "pix"
    }.merge(overrides)
  end

  def stub_payment_check(overrides = {})
    body = {
      "success" => true, "paid" => true, "amount" => @order.total_cents,
      "paid_amount" => @order.total_cents, "installments" => 1, "capture_method" => "pix"
    }
    stub_request(:post, CHECK_URL).to_return(
      status: 200, body: body.merge(overrides).to_json, headers: { "Content-Type" => "application/json" }
    )
  end

  test "captures the event, enqueues processing, and answers 200 without processing inline" do
    assert_enqueued_with(job: Payments::ProcessWebhookJob) do
      webhook(@order.webhook_token, paid_payload("invoice_slug" => "uXnT2kndIV"))
    end

    assert_response :ok
    assert @order.reload.awaiting_payment?, "processing is deferred to the job"
    event = @order.payment_webhook_events.last
    assert_equal "uXnT2kndIV", event.payload["invoice_slug"]
    assert event.headers["CONTENT_TYPE"].present?
  end

  test "the enqueued job confirms the order and records the payment fields" do
    perform_enqueued_jobs do
      webhook(@order.webhook_token, paid_payload("transaction_nsu" => "tx-confirm"))
    end

    assert_response :ok
    @order.reload
    assert @order.payment_confirmed?
    assert_equal "tx-confirm", @order.external_id
    assert_equal "uXnT2kndIV", @order.invoice_slug
  end

  test "an unknown token is rejected with 401 and captures + enqueues nothing" do
    assert_no_enqueued_jobs do
      assert_no_difference "PaymentWebhookEvent.count" do
        webhook("nope-#{SecureRandom.hex(4)}", paid_payload)
      end
    end

    assert_response :unauthorized
    assert @order.reload.awaiting_payment?
  end

  test "a replayed webhook captures + enqueues each delivery and stays idempotent" do
    body = paid_payload("transaction_nsu" => "tx-once")
    perform_enqueued_jobs do
      webhook(@order.webhook_token, body)
      webhook(@order.webhook_token, body)
    end

    assert_response :ok
    @order.reload
    assert @order.payment_confirmed?
    assert_equal "tx-once", @order.external_id
    assert_equal 2, @order.payment_webhook_events.count
  end

  test "a delivery infinitepay reports as unpaid answers 200 but never confirms the order" do
    stub_payment_check("paid" => false)

    perform_enqueued_jobs { webhook(@order.webhook_token, paid_payload) }

    assert_response :ok
    assert @order.reload.awaiting_payment?
  end

  test "a delivery for a transaction infinitepay does not recognize never confirms the order" do
    stub_payment_check("success" => false, "paid" => false)

    perform_enqueued_jobs { webhook(@order.webhook_token, paid_payload) }

    assert_response :ok
    assert @order.reload.awaiting_payment?
  end

  test "the amount that counts is the one infinitepay reports, not the one in the delivery" do
    stub_payment_check("paid_amount" => 1)

    perform_enqueued_jobs { webhook(@order.webhook_token, paid_payload("paid_amount" => @order.total_cents)) }

    assert_response :ok
    assert @order.reload.awaiting_payment?
  end

  test "a paid_amount above the order total (installment interest) confirms the order" do
    stub_payment_check("paid_amount" => @order.total_cents + 2_802, "installments" => 3)

    perform_enqueued_jobs { webhook(@order.webhook_token, paid_payload) }

    assert_response :ok
    assert @order.reload.payment_confirmed?
  end

  test "a mismatched order_nsu answers 200 but leaves the order awaiting payment" do
    perform_enqueued_jobs { webhook(@order.webhook_token, paid_payload("order_nsu" => "PG-000000000000")) }

    assert_response :ok
    assert @order.reload.awaiting_payment?
    assert_not_requested(:post, CHECK_URL)
  end

  test "a valid token with an empty body captures the delivery and is a no-op" do
    perform_enqueued_jobs { webhook(@order.webhook_token, {}) }

    assert_response :ok
    assert @order.reload.awaiting_payment?
    assert_not_requested(:post, CHECK_URL)
  end
end
