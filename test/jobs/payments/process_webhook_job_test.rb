require "test_helper"

module Payments
  class ProcessWebhookJobTest < ActiveSupport::TestCase
    def order
      @order ||= Order.create!(user: users(:confirmed), subtotal_cents: 18_000, total_cents: 19_984)
    end

    def store_event(overrides = {})
      order.payment_webhook_events.create!(headers: {}, payload: {
        "order_nsu" => order.number, "paid_amount" => order.total_cents,
        "transaction_nsu" => "tx-1", "receipt_url" => "https://recibo/tx", "capture_method" => "pix"
      }.merge(overrides))
    end

    test "processes the stored event through PaymentUpdate" do
      event = store_event

      Payments::ProcessWebhookJob.perform_now(event.id)

      assert order.reload.payment_confirmed?
      assert_equal "tx-1", order.external_id
    end

    test "is a no-op when the event was already purged" do
      assert_nothing_raised { Payments::ProcessWebhookJob.perform_now(-1) }
    end
  end
end
