require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  test "slug must be unique" do
    dup = Category.new(name: "Dup", slug: categories(:gb_color).slug)
    assert_not dup.valid?
    assert_includes dup.errors[:slug], "has already been taken"
  end

  test "deletion is blocked while products exist" do
    category = categories(:gb_color)
    assert_not category.destroy
    assert_includes category.errors[:base].join, "Cannot delete"
  end

  test "default scope orders by position" do
    assert_equal Category.order(:position).to_a, Category.all.to_a
  end
end
