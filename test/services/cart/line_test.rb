require "test_helper"

class Cart::LineTest < ActiveSupport::TestCase
  test "unit_price_cents sums product price + option deltas" do
    line = Cart::Line.new(
      id: "abc123",
      product: products(:yellow),
      quantity: 1,
      options: [ product_options(:yellow_caixa_com) ]
    )
    assert_equal 19_000, line.unit_price_cents
    assert_equal "R$ 190.00", line.unit_price_formatted
  end

  test "line_total_cents multiplies unit_price by quantity" do
    line = Cart::Line.new(
      id: "abc123",
      product: products(:yellow),
      quantity: 3,
      options: []
    )
    assert_equal 54_000, line.line_total_cents
    assert_equal "R$ 540.00", line.line_total_formatted
  end

  test "selected_for returns the option in the requested group" do
    pt = product_options(:yellow_idioma_pt)
    line = Cart::Line.new(
      id: "abc123",
      product: products(:yellow),
      quantity: 1,
      options: [ pt, product_options(:yellow_caixa_com) ]
    )
    assert_equal pt, line.selected_for("Idioma")
    assert_nil line.selected_for("Etiqueta")
  end

  test "weight_grams sums the product's base weight + every option's delta" do
    line = Cart::Line.new(
      id: "abc123",
      product: products(:yellow), # 22g base
      quantity: 4, # quantity is irrelevant at the line level — that's Bag's job
      options: [
        product_options(:yellow_idioma_pt),  # 0g
        product_options(:yellow_caixa_com)   # +38g
      ]
    )
    assert_equal 60, line.weight_grams
  end

  test "weight_grams returns just the base when no options are selected" do
    line = Cart::Line.new(
      id: "abc123",
      product: products(:yellow), # 22g
      quantity: 1,
      options: []
    )
    assert_equal 22, line.weight_grams
  end
end
