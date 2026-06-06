require "test_helper"

class ProductPhotoTest < ActiveSupport::TestCase
  test "a photo belongs to a product" do
    photo = ProductPhoto.new(product: products(:metroid))
    assert photo.valid?
  end
end
