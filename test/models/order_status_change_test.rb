require "test_helper"

class OrderStatusChangeTest < ActiveSupport::TestCase
  test "belongs to an order and the acting operator" do
    change = order_status_changes(:delivered_production)
    assert_equal orders(:delivered), change.order
    assert_equal users(:admin), change.actor
    assert_not change.automatic
  end

  test "an automatic change has no actor" do
    change = order_status_changes(:delivered_paid)
    assert change.automatic
    assert_nil change.actor
  end

  test "chronological orders by created_at then id" do
    statuses = orders(:delivered).status_changes.chronological.pluck(:to_status)
    assert_equal %w[awaiting_payment payment_confirmed in_production label_issued shipped delivered], statuses
  end
end
