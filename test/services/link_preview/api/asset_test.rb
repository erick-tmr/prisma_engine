require "test_helper"

module LinkPreview
  module Api
    class AssetTest < ActiveSupport::TestCase
      URL = "https://example.com/favicon.ico".freeze

      def with_safe_url(&block)
        SafeUrl.stub(:call, ->(url) { url }, &block)
      end

      test "returns the favicon bytes and content type" do
        stub_request(:get, URL).to_return(status: 200, body: "BINARY", headers: { "Content-Type" => "image/png" })

        result = with_safe_url { Asset.fetch(URL) }

        assert_equal "BINARY", result[:bytes]
        assert_equal "image/png", result[:content_type]
      end

      test "falls back to image/x-icon when the content type is missing" do
        stub_request(:get, URL).to_return(status: 200, body: "BIN")

        assert_equal "image/x-icon", with_safe_url { Asset.fetch(URL) }[:content_type]
      end

      test "raises a non-transient Error on a 404" do
        stub_request(:get, URL).to_return(status: 404)
        error = assert_raises(Error) { with_safe_url { Asset.fetch(URL) } }
        refute_kind_of TransientError, error
      end

      test "raises TransientError on a 503" do
        stub_request(:get, URL).to_return(status: 503)
        assert_raises(TransientError) { with_safe_url { Asset.fetch(URL) } }
      end

      test "decodes a percent-encoded data URI without hitting the network" do
        result = Asset.fetch("data:image/svg+xml,%3Csvg%3E%3C/svg%3E")
        assert_equal "<svg></svg>", result[:bytes]
        assert_equal "image/svg+xml", result[:content_type]
      end

      test "decodes a base64 data URI" do
        encoded = Base64.strict_encode64("PNGDATA")
        result = Asset.fetch("data:image/png;base64,#{encoded}")
        assert_equal "PNGDATA", result[:bytes]
        assert_equal "image/png", result[:content_type]
      end

      test "defaults the content type of a typeless data URI" do
        assert_equal "text/plain", Asset.fetch("data:,hello")[:content_type]
      end

      test "raises Error on a data URI without a comma" do
        assert_raises(Error) { Asset.fetch("data:image/png") }
      end
    end
  end
end
