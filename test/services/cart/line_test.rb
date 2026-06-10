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
end
