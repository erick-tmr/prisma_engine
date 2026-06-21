require "test_helper"
require "active_storage/service/disk_service"

module Storage
  class BlobMigratorTest < ActiveSupport::TestCase
    IMAGE = Rails.root.join("public/images/stores/uploads/2475313/conversions/large.jpg")

    setup do
      @root = Dir.mktmpdir
      @destination = ActiveStorage::Service::DiskService.new(root: @root)
      @photo = products(:metroid).product_photos.create!(position: 0)
      @photo.image.attach(io: File.open(IMAGE), filename: "large.jpg", content_type: "image/jpeg")
      @blob = @photo.image.blob
    end

    teardown { FileUtils.remove_entry(@root) }

    test "copies blobs to the destination and stamps the service name" do
      count = Storage::BlobMigrator.new(destination: @destination, name: :scratch).call

      assert_equal 1, count
      assert @destination.exist?(@blob.key)
      assert_equal "scratch", @blob.reload.service_name
    end

    test "skips re-uploading blobs already present on the destination but still stamps them" do
      existing = "already-there"
      @destination.upload(@blob.key, StringIO.new(existing), checksum: OpenSSL::Digest::MD5.base64digest(existing))

      Storage::BlobMigrator.new(destination: @destination, name: :scratch).call

      assert_equal existing, @destination.download(@blob.key)
      assert_equal "scratch", @blob.reload.service_name
    end

    test "ignores blobs already stamped with the destination service name" do
      @blob.update_column(:service_name, "scratch")

      assert_equal 0, Storage::BlobMigrator.new(destination: @destination, name: :scratch).call
    end
  end
end
