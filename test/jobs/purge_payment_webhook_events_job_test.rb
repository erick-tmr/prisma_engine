require "test_helper"

class PurgePaymentWebhookEventsJobTest < ActiveJob::TestCase
  setup do
    @order = Order.create!(
      user: users(:confirmed),
      subtotal_cents: 18_000, total_cents: 19_984,
    )
  end

  test "deletes events past the retention window and keeps recent ones" do
    stale  = @order.payment_webhook_events.create!(headers: {}, payload: {})
    stale.update_column(:created_at, (PurgePaymentWebhookEventsJob::RETENTION + 1.day).ago)
    recent = @order.payment_webhook_events.create!(headers: {}, payload: {})

    PurgePaymentWebhookEventsJob.perform_now

    assert_not PaymentWebhookEvent.exists?(stale.id)
    assert PaymentWebhookEvent.exists?(recent.id)
  end
end
