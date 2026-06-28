require "test_helper"

class ProductionBatchTest < ActiveSupport::TestCase
  test "an operator is optional and the order link nullifies on destroy" do
    batch = ProductionBatch.create!(orders_count: 1)
    order = Order.create!(user: users(:confirmed), status: "in_production",
                          subtotal_cents: 1_000, total_cents: 1_000, production_batch: batch)

    assert_nil batch.operator
    assert_equal [ order ], batch.orders.to_a

    batch.destroy
    assert_nil order.reload.production_batch_id
  end

  test "recent_first orders newest batch first" do
    older = ProductionBatch.create!(orders_count: 1, created_at: 2.days.ago)
    newer = ProductionBatch.create!(orders_count: 1, created_at: 1.hour.ago)

    assert_equal [ newer, older ], ProductionBatch.recent_first.to_a
  end
end
