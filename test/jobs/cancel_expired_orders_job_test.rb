require "test_helper"

class CancelExpiredOrdersJobTest < ActiveSupport::TestCase
  def build_order
    Order.create!(
      user: users(:confirmed), subtotal_cents: 18_000, shipping_cents: 1_984, total_cents: 19_984,
      shipping_service: "pac",
      ship_receiver_name: "Cliente", ship_receiver_cpf: "52998224725",
      ship_zip: "01310100", ship_street: "Av. Paulista", ship_number: "1578",
      ship_neighborhood: "Bela Vista", ship_city: "São Paulo", ship_state: "SP"
    )
  end

  test "cancels only awaiting-payment orders past the 24h deadline" do
    fresh = build_order
    stale = build_order
    stale.update_column(:created_at, 25.hours.ago)
    paid = build_order
    paid.update_column(:created_at, 25.hours.ago)
    paid.confirm_payment!

    CancelExpiredOrdersJob.perform_now

    assert stale.reload.cancelled?
    assert fresh.reload.awaiting_payment?
    assert paid.reload.payment_confirmed?
  end
end
