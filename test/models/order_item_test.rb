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

  test "game? is true for a catalog game, false for an accessory or a detached snapshot" do
    assert build_item(product: products(:metroid)).game?
    assert_not build_item(product: products(:game_box)).game?
    assert_not build_item(product: nil).game?
  end

  test "the games scope keeps cartridges and drops accessory items" do
    order.order_items.create!(name: "Metroid", unit_price_cents: 1, quantity: 1, product: products(:metroid))
    order.order_items.create!(name: "Caixa", unit_price_cents: 1, quantity: 1, product: products(:game_box))

    names = order.order_items.games.pluck(:name)
    assert_includes names, "Metroid"
    assert_not_includes names, "Caixa"
  end
end
