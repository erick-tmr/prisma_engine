require "test_helper"

class ProductPhotoTest < ActiveSupport::TestCase
  test "a variant-scoped photo must belong to the same product" do
    photo = ProductPhoto.new(
      product: products(:metroid), variant: variants(:yellow_master)
    )
    assert_not photo.valid?
    assert_includes photo.errors[:variant], "must belong to the same product"
  end

  test "a photo may be product-wide (no variant)" do
    photo = ProductPhoto.new(product: products(:metroid))
    assert photo.valid?
  end
end
