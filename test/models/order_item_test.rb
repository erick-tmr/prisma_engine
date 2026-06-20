require "test_helper"

class OrderItemTest < ActiveSupport::TestCase
  def order
    @order ||= Order.create!(
      user: users(:confirmed),
      subtotal_cents: 32_000, total_cents: 34_990,
    )
  end

  def build_item(overrides = {})
    order.order_items.build(
      { name: "Cartucho", unit_price_cents: 32_000, quantity: 2, chosen_options: [ "ROM: Zelda" ] }.merge(overrides)
    )
  end

  test "a fully-populated item is valid" do
    item = build_item
    assert item.valid?, item.errors.full_messages.to_sentence
  end

  test "line_total_cents multiplies unit price by quantity" do
    assert_equal 64_000, build_item.line_total_cents
  end

  test "name is required" do
    assert_not build_item(name: nil).valid?
  end

  test "unit_price_cents rejects negatives" do
    assert_not build_item(unit_price_cents: -1).valid?
  end

  test "quantity must be positive" do
    assert_not build_item(quantity: 0).valid?
  end

  test "product is optional — the snapshot stands without a catalog link" do
    assert build_item(product: nil).valid?
  end
end
