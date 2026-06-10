require "test_helper"

class ProductOptionTest < ActiveSupport::TestCase
  test "name is required" do
    option = ProductOption.new(product: products(:metroid))
    assert_not option.valid?
    assert_includes option.errors[:name], "não pode ficar em branco"
  end

  test "price_delta_cents allows zero and positive values" do
    option = ProductOption.new(
      product: products(:metroid), name: "Sem caixa", price_delta_cents: 0
    )
    assert option.valid?
  end

  test "same name cannot repeat within a product+group" do
    dup = ProductOption.new(
      product: products(:yellow), group_name: "Idioma", name: "Português BR"
    )
    assert_not dup.save
  end

  test "same name may repeat across products" do
    ok = ProductOption.new(
      product: products(:metroid), group_name: "Idioma", name: "Português BR"
    )
    assert ok.valid?
  end

  test "in_display_order returns options by position" do
    ordered = products(:yellow).product_options.in_display_order
    assert_equal [ 0, 1, 2, 3 ], ordered.pluck(:position)
  end

  test "price_delta_formatted reuses HasMoney" do
    assert_equal "R$ 10.00", product_options(:yellow_caixa_com).price_delta_formatted
  end

  test "weight_delta_grams must be a non-negative integer" do
    option = ProductOption.new(
      product: products(:metroid), name: "Negativo", weight_delta_grams: -1
    )
    assert_not option.valid?

    option.weight_delta_grams = 1.5
    assert_not option.valid?

    option.weight_delta_grams = 0
    assert option.valid?
  end
end
