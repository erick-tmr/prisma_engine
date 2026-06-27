require "test_helper"

module Production
  class EligibleOrdersTest < ActiveSupport::TestCase
    def make_order(status:, created_at: 1.day.ago, items: [ {} ])
      order = Order.create!(
        user: users(:confirmed), status: status,
        subtotal_cents: 1_000, total_cents: 1_000, created_at: created_at
      )
      items.each do |attrs|
        defaults = { product: products(:metroid), name: "Cartucho", unit_price_cents: 1_000, quantity: 1, chosen_options: [] }
        order.order_items.create!(defaults.merge(attrs))
      end
      order
    end

    test "STATUSES mirror the to_production move" do
      assert_equal Admin::OrderActions.lookup("to_production").from, EligibleOrders::STATUSES
    end

    test "returns only paid-to-produce orders that contain a game" do
      eligible = make_order(status: "payment_confirmed")
      accessories_only = make_order(status: "payment_confirmed", items: [ { product: products(:game_box) } ])
      wrong_status = make_order(status: "awaiting_payment")

      numbers = EligibleOrders.within.map(&:number)
      assert_includes numbers, eligible.number
      assert_not_includes numbers, accessories_only.number
      assert_not_includes numbers, wrong_status.number
      EligibleOrders.within.each { |order| assert_includes EligibleOrders::STATUSES, order.status }
    end

    test "narrows to a period, oldest first" do
      older = make_order(status: "payment_confirmed", created_at: Time.zone.local(2026, 1, 10, 9))
      newer = make_order(status: "production_issue", created_at: Time.zone.local(2026, 1, 15, 9))
      make_order(status: "payment_confirmed", created_at: Time.zone.local(2025, 12, 31, 9)) # outside the window

      result = EligibleOrders.within(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 31)).map(&:number)
      assert_equal [ older.number, newer.number ], result
    end

    test "an open-ended period bounds only the given side" do
      make_order(status: "payment_confirmed", created_at: Time.zone.local(2026, 1, 10, 9))
      make_order(status: "payment_confirmed", created_at: Time.zone.local(2026, 3, 10, 9))

      from_dates = EligibleOrders.within(from: Date.new(2026, 2, 1)).map { |order| order.created_at.to_date.iso8601 }
      assert_includes from_dates, "2026-03-10"
      assert_not_includes from_dates, "2026-01-10"

      to_dates = EligibleOrders.within(to: Date.new(2026, 2, 1)).map { |order| order.created_at.to_date.iso8601 }
      assert_includes to_dates, "2026-01-10"
      assert_not_includes to_dates, "2026-03-10"
    end
  end
end
