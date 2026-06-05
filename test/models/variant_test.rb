require "test_helper"

class VariantTest < ActiveSupport::TestCase
  test "sku must be unique" do
    dup = Variant.new(product: products(:metroid), sku: variants(:yellow_master).sku)
    assert_not dup.valid?
    assert_includes dup.errors[:sku], "has already been taken"
  end

  test "a product cannot have two master variants" do
    second = Variant.new(
      product: products(:yellow), sku: "TEST-SECOND-MASTER", is_master: true
    )
    assert_not second.valid?
    assert_includes second.errors[:is_master], "product already has a master variant"
  end

  test "computed_price_cents adds option value contributions" do
    assert_equal 19000, variants(:yellow_boxed).computed_price_cents
    assert_equal 18000, variants(:yellow_master).computed_price_cents
  end

  test "available scope" do
    assert_includes Variant.available, variants(:yellow_master)
  end

  test "a sole master variant is valid" do
    assert variants(:yellow_master).valid?
  end
end
