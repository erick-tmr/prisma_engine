require "test_helper"

class PurgePaymentWebhookEventsJobTest < ActiveJob::TestCase
  setup do
    @order = Order.create!(
      user: users(:confirmed),
      subtotal_cents: 18_000, shipping_cents: 1_984, total_cents: 19_984,
      shipping_service: "sedex",
      ship_receiver_name: "Cliente Confirmado", ship_receiver_cpf: "52998224725",
      ship_zip: "01310100", ship_street: "Av. Paulista", ship_number: "1578",
      ship_neighborhood: "Bela Vista", ship_city: "São Paulo", ship_state: "SP"
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
