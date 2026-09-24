require "test_helper"

module Production
  class SendOrdersTest < ActiveSupport::TestCase
    def make_order(status)
      Order.create!(user: users(:confirmed), status: status, subtotal_cents: 1, total_cents: 1)
    end

    test "sends every waiting or blocked order to production on behalf of the operator" do
      waiting = EligibleOrders::ENTERING.map { |status| make_order(status) }

      sent = SendOrders.call(orders: Order.where(id: waiting.map(&:id)), operator: users(:admin))

      assert_equal waiting.map(&:id).sort, sent.map(&:id).sort
      waiting.each do |order|
        assert order.reload.in_production?
        change = order.status_changes.chronological.last
        assert_equal "in_production", change.to_status
        assert_equal users(:admin), change.actor
      end
    end

    test "leaves orders already in production untouched" do
      producing = make_order("in_production")

      assert_no_difference -> { producing.status_changes.count } do
        sent = SendOrders.call(orders: Order.where(id: producing.id), operator: users(:admin))
        assert_equal [ producing ], sent
      end

      assert producing.reload.in_production?
    end
  end
end
