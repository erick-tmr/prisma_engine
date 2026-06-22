require "test_helper"

module Storefront
  class ImageSourceTest < ActiveSupport::TestCase
    IMAGE = Rails.root.join("public/images/stores/uploads/2475313/conversions/large.jpg")

    test "returns a same-origin blob path for a non-public (disk) service" do
      photo = products(:metroid).product_photos.create!(position: 0)
      photo.image.attach(io: File.open(IMAGE), filename: "large.jpg", content_type: "image/jpeg")

      assert_match %r{\A/rails/active_storage/}, Storefront::ImageSource.call(photo.image)
    end

    test "returns the service public URL for a public service" do
      service = Object.new
      def service.public? = true
      blob = Object.new
      blob.define_singleton_method(:service) { service }
      blob.define_singleton_method(:url) { "https://cdn.example.test/key123" }
      attachment = Object.new
      attachment.define_singleton_method(:blob) { blob }

      assert_equal "https://cdn.example.test/key123", Storefront::ImageSource.call(attachment)
    end
  end
end
