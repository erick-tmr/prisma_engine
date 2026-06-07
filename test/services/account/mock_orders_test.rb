require "test_helper"

module Account
  class MockOrdersTest < ActiveSupport::TestCase
    test "all_for returns 5 orders" do
      assert_equal 5, MockOrders.all_for(users(:confirmed)).size
    end

    test "all_for covers the 5 distinct customer-facing states" do
      statuses = MockOrders.all_for(users(:confirmed)).map(&:status)
      assert_equal %w[aguardando_pagamento em_producao enviado entregue pagamento_confirmado].sort,
                   statuses.sort
    end

    test "find returns the matching mock" do
      order = MockOrders.find(users(:confirmed), "PG-2026-000001")
      assert_not_nil order
      assert_equal "aguardando_pagamento", order.status
    end

    test "find returns nil for an unknown number" do
      assert_nil MockOrders.find(users(:confirmed), "UNKNOWN")
    end

    test "to_param returns the order number" do
      order = MockOrders.find(users(:confirmed), "PG-2026-000001")
      assert_equal "PG-2026-000001", order.to_param
    end

    test "cancellable? is true for early states and false after production" do
      orders_by_status = MockOrders.all_for(users(:confirmed)).index_by(&:status)
      assert orders_by_status.fetch("aguardando_pagamento").cancellable?
      assert orders_by_status.fetch("pagamento_confirmado").cancellable?
      assert_not orders_by_status.fetch("em_producao").cancellable?
      assert_not orders_by_status.fetch("enviado").cancellable?
      assert_not orders_by_status.fetch("entregue").cancellable?
    end

    test "shipping_visible? is true once sent" do
      orders_by_status = MockOrders.all_for(users(:confirmed)).index_by(&:status)
      assert orders_by_status.fetch("enviado").shipping_visible?
      assert orders_by_status.fetch("entregue").shipping_visible?
      assert_not orders_by_status.fetch("em_producao").shipping_visible?
      assert_not orders_by_status.fetch("aguardando_pagamento").shipping_visible?
    end

    test "MockOrderItem#line_total_cents multiplies unit price by quantity" do
      item = Account::MockOrderItem.new(
        name: "X",
        unit_price_cents: 1_000,
        quantity: 3,
        chosen_options: [],
        photo_path: "/x.png"
      )
      assert_equal 3_000, item.line_total_cents
    end

    test "totals are subtotal + shipping" do
      order = MockOrders.find(users(:confirmed), "PG-2026-000005")
      assert_equal order.subtotal_cents + order.shipping_cents, order.total_cents
    end
  end
end
