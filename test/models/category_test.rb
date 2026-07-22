require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  test "slug must be unique" do
    dup = Category.new(name: "Dup", slug: categories(:gb_color).slug)
    assert_not dup.valid?
    assert_includes dup.errors[:slug], "já está em uso"
  end

  test "deletion is blocked while products exist" do
    category = categories(:gb_color)
    assert_not category.destroy
    assert_includes category.errors[:base].join, "Não é possível excluir"
  end
end
