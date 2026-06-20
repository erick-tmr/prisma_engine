require "test_helper"

class CancelExpiredOrdersJobTest < ActiveSupport::TestCase
  def build_order
    Order.create!(
      user: users(:confirmed), subtotal_cents: 18_000, total_cents: 19_984,
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
