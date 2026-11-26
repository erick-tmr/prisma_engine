require "test_helper"

module Storage
  class AssetUploadTest < ActiveSupport::TestCase
    setup { @path = file_fixture("sample_product.jpg") }

    test "uploads the bytes under a fresh Active Storage key and describes them" do
      result = AssetUpload.call(@path)

      assert_equal ActiveStorage::Blob::MINIMUM_TOKEN_LENGTH, result.key.length
      assert_equal "sample_product.jpg", result.filename
      assert_equal "image/jpeg", result.content_type
      assert_equal @path.size, result.byte_size
      assert_equal OpenSSL::Digest::MD5.file(@path).base64digest, result.checksum
      assert_equal "test", result.service_name
      assert_nil result.url
      assert_equal @path.binread, ActiveStorage::Blob.service.download(result.key)
    end

    test "writes no database rows: the console step does that" do
      assert_no_difference -> { ActiveStorage::Blob.count } do
        AssetUpload.call(@path)
      end
    end

    test "the console snippet creates a blob that serves the uploaded file" do
      result = AssetUpload.call(@path)

      blob = eval(result.console_snippet) # rubocop:disable Security/Eval

      assert blob.persisted?
      assert_equal result.key, blob.key
      assert blob.analyzed?
      assert_equal @path.binread, blob.download
    end

    test "a public service reports the URL the file is served from" do
      service = ActiveStorage::Blob.service
      service.stub(:public?, true) do
        service.stub(:url, ->(key) { "https://cdn.example.test/#{key}" }) do
          result = AssetUpload.call(@path, service:)

          assert_equal "https://cdn.example.test/#{result.key}", result.url
        end
      end
    end
  end
end
