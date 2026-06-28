require "test_helper"

module Production
  class SendBatchTest < ActiveSupport::TestCase
    test "records a batch, sends each order to production and stamps them" do
      paid = Order.create!(user: users(:confirmed), status: "payment_confirmed", subtotal_cents: 1, total_cents: 1)
      components = Order.create!(user: users(:confirmed), status: "awaiting_components", subtotal_cents: 1, total_cents: 1)

      batch = SendBatch.call(
        orders: Order.where(id: [ paid.id, components.id ]),
        operator: users(:admin), from: Date.new(2026, 6, 1), to: Date.new(2026, 6, 7)
      )

      assert_equal users(:admin), batch.operator
      assert_equal Date.new(2026, 6, 1), batch.period_from
      assert_equal Date.new(2026, 6, 7), batch.period_to
      assert_equal 2, batch.orders_count
      assert paid.reload.in_production?
      assert components.reload.in_production?
      assert_equal batch, paid.production_batch
      assert_equal batch, components.production_batch

      change = paid.status_changes.chronological.last
      assert_equal "in_production", change.to_status
      assert_equal users(:admin), change.actor
    end

    test "rolls the whole batch back when any transition is invalid" do
      good = Order.create!(user: users(:confirmed), status: "payment_confirmed", subtotal_cents: 1, total_cents: 1)
      bad = Order.create!(user: users(:confirmed), status: "delivered", subtotal_cents: 1, total_cents: 1) # cannot enter production

      assert_no_difference -> { ProductionBatch.count } do
        assert_raises(Order::InvalidTransition) do
          SendBatch.call(orders: Order.where(id: [ good.id, bad.id ]).order(:id), operator: users(:admin))
        end
      end

      assert good.reload.payment_confirmed?, "the valid order's transition must roll back with the batch"
    end
  end
end
