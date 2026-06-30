require "test_helper"

module LinkPreview
  module Api
    class SafeUrlTest < ActiveSupport::TestCase
      test "returns the url for a public host" do
        Resolv.stub(:getaddresses, [ "93.184.216.34" ]) do
          assert_equal "https://example.com", SafeUrl.call("https://example.com")
        end
      end

      test "rejects a loopback address" do
        Resolv.stub(:getaddresses, [ "127.0.0.1" ]) do
          assert_raises(Error) { SafeUrl.call("http://localhost.example") }
        end
      end

      test "rejects a private RFC1918 address" do
        Resolv.stub(:getaddresses, [ "10.0.0.5" ]) do
          assert_raises(Error) { SafeUrl.call("http://intranet.example") }
        end
      end

      test "rejects the cloud metadata address" do
        Resolv.stub(:getaddresses, [ "169.254.169.254" ]) do
          assert_raises(Error) { SafeUrl.call("http://metadata.example") }
        end
      end

      test "rejects an IPv6 loopback address" do
        Resolv.stub(:getaddresses, [ "::1" ]) do
          assert_raises(Error) { SafeUrl.call("http://v6.example") }
        end
      end

      test "rejects a non-http scheme" do
        assert_raises(Error) { SafeUrl.call("ftp://example.com") }
      end

      test "rejects an http url without a host" do
        assert_raises(Error) { SafeUrl.call("http:///path") }
      end

      test "raises TransientError when the host cannot be resolved" do
        Resolv.stub(:getaddresses, []) do
          assert_raises(TransientError) { SafeUrl.call("https://nope.example") }
        end
      end

      test "raises Error on a malformed url" do
        assert_raises(Error) { SafeUrl.call("http://exa mple") }
      end
    end
  end
end
