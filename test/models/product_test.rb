require "test_helper"

class ProductTest < ActiveSupport::TestCase
  test "slug is normalized from a title carrying HTML entities and emoji" do
    product = Product.create!(
      category: categories(:gb_color),
      name: "Kirby&#039;s Dream Land 2 🔴",
      price_cents: 18000,
      weight_grams: 22
    )
    assert_equal "kirbys-dream-land-2", product.slug
  end

  test "weight_grams is required and must be a positive integer" do
    product = Product.new(category: categories(:gb_color), name: "Test", price_cents: 18000)
    assert_not product.valid?
    assert_includes product.errors[:weight_grams], "não pode ficar em branco"

    product.weight_grams = 0
    assert_not product.valid?
    assert_includes product.errors[:weight_grams], "deve ser maior que 0"

    product.weight_grams = 22.5
    assert_not product.valid?

    product.weight_grams = 22
    assert product.valid?
  end

  test "for_category returns only that category's products" do
    slugs = Product.for_category("game-boy-classic").pluck(:slug)
    assert_includes slugs, products(:metroid).slug
    assert_not_includes slugs, products(:yellow).slug
  end

  test "featured excludes placeholder and unpublished products and respects the limit" do
    names = Product.featured.map(&:name)
    assert_not_includes names, products(:placeholder).name
    assert_not_includes names, products(:hidden).name
    assert_operator Product.featured(1).size, :<=, 1
  end

  test "price_formatted matches the legacy PORO output" do
    assert_equal "R$ 180.00", products(:yellow).price_formatted
    assert_equal "Sob consulta", products(:hidden).price_formatted
  end

  test "image falls back to legacy_image_path when no photo is attached" do
    assert_equal "/images/test-yellow.jpg", products(:yellow).image
  end

  test "image returns the Active Storage blob path when a photo is attached" do
    product = products(:metroid)
    photo = product.product_photos.create!(alt_text: product.name, position: 0)
    photo.image.attach(
      io: File.open(Rails.root.join("public/images/stores/uploads/2475313/conversions/large.jpg")),
      filename: "large.jpg",
      content_type: "image/jpeg"
    )
    assert_match %r{/rails/active_storage/}, product.reload.image
  end

  test "friendly finder resolves a historical slug after a rename" do
    assert_equal products(:yellow), Product.friendly.find("pokemon-amarelo")
  end

  test "interface shims preserved from the former PORO" do
    yellow = products(:yellow)
    assert_equal yellow.name, yellow.title
    assert_equal "Game Boy Color", yellow.category_label
  end

  test "category_label is nil when no category is associated" do
    assert_nil Product.new.category_label
  end
end
