require "test_helper"

class CheckoutHelperTest < ActionView::TestCase
  include StorefrontImageHelper

  def order_with(item_attrs)
    order = users(:confirmed).orders.create!(subtotal_cents: 18_000, total_cents: 20_000)
    order.order_items.create!({ name: "Item", unit_price_cents: 18_000, quantity: 1 }.merge(item_attrs))
    order
  end

  test "merge_order_meta shows the item count and the product category" do
    order = order_with(product: products(:yellow), photo_path: products(:yellow).image)
    assert_equal "1 item · #{products(:yellow).category_label}", merge_order_meta(order)
  end

  test "merge_order_meta labels a made-to-order line as Pedido de jogo" do
    order = order_with(requested_game: "Zelda Redux")
    assert_equal "1 item · Pedido de jogo", merge_order_meta(order)
  end

  test "merge_order_meta drops the category when the product is gone" do
    order = order_with({})
    assert_equal "1 item", merge_order_meta(order)
  end

  test "merge_order_thumb renders the product image when a photo is present" do
    item = order_with(photo_path: products(:yellow).image).order_items.first
    html = merge_order_thumb(item)
    assert_includes html, "checkout__merge-thumb"
    assert_includes html, "<img"
  end

  test "merge_order_thumb falls back to the pedido icon without a photo" do
    item = order_with(requested_game: "Zelda").order_items.first
    html = merge_order_thumb(item)
    assert_includes html, "checkout__merge-thumb--pedido"
    assert_includes html, "bi-card-checklist"
  end

  test "merge_order_thumbs concatenates a thumb per item" do
    order = order_with(photo_path: products(:yellow).image)
    order.order_items.create!(name: "Segundo", unit_price_cents: 100, quantity: 1)
    assert_equal 2, merge_order_thumbs(order).scan('class="checkout__merge-thumb').size
  end
end
