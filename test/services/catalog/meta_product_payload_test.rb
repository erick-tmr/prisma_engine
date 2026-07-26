require "test_helper"

module Catalog
  class MetaProductPayloadTest < ActiveSupport::TestCase
    def upload
      Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/sample_product.jpg"), "image/jpeg")
    end

    def build_product(**attrs)
      Product.create!({
        name: "Zelda", category: categories(:gb_color), weight_grams: 60,
        price_cents: 19_990, description: "<p>Cartucho &amp; manual</p>"
      }.merge(attrs))
    end

    test "maps product attributes to the Meta item fields" do
      product = build_product
      product.product_photos.create!(position: 0).image.attach(upload)

      payload = Catalog::MetaProductPayload.call(product)

      assert_equal "Zelda", payload[:title]
      assert_equal "Cartucho & manual", payload[:description]
      assert_equal "in stock", payload[:availability]
      assert_equal "new", payload[:condition]
      assert_equal "Prisma Games", payload[:brand]
      assert_equal "199.90 BRL", payload[:price]
      assert_not payload.key?(:currency)
      assert_equal false, payload[:identifier_exists]
      assert_equal "Toys & Games > Games", payload[:google_product_category]
      assert_match %r{//example\.com/produto/zelda\z}, payload[:link]
    end

    test "orders images by position and skips photos without an attached image" do
      product = build_product
      product.product_photos.create!(position: 1).image.attach(upload)
      product.product_photos.create!(position: 0).image.attach(upload)
      product.product_photos.create!(position: 2)

      payload = Catalog::MetaProductPayload.call(product)

      assert payload[:image_link].present?
      assert_equal 1, payload[:additional_image_link].length
    end

    test "falls back to the product name when the description is blank" do
      product = build_product(description: "")
      product.product_photos.create!(position: 0).image.attach(upload)

      assert_equal "Zelda", Catalog::MetaProductPayload.call(product)[:description]
    end

    test "uses the miscellaneous google category for non-game products" do
      product = build_product(name: "Carcaca", category: categories(:miscelanea))
      product.product_photos.create!(position: 0).image.attach(upload)

      assert_equal "Toys & Games", Catalog::MetaProductPayload.call(product)[:google_product_category]
    end
  end
end
