require "test_helper"

class ProductOptionTypeTest < ActiveSupport::TestCase
  test "the same option_type cannot be attached to a product twice" do
    product = products(:yellow)
    ProductOptionType.create!(product: product, option_type: option_types(:idioma))

    dup = ProductOptionType.new(product: product, option_type: option_types(:idioma))
    assert_not dup.valid?
    assert_includes dup.errors[:option_type_id], "has already been taken"
  end

  test "the same option_type may be attached to different products" do
    ProductOptionType.create!(product: products(:yellow), option_type: option_types(:idioma))

    other = ProductOptionType.new(product: products(:metroid), option_type: option_types(:idioma))
    assert other.valid?
  end

  test "default_scope orders by position" do
    product = products(:metroid)
    later = ProductOptionType.create!(product: product, option_type: option_types(:caixa), position: 1)
    first = ProductOptionType.create!(product: product, option_type: option_types(:idioma), position: 0)

    assert_equal [ first, later ], ProductOptionType.where(product: product).to_a
  end
end
