require "test_helper"

module LinkPreview
  module Api
    class PageTest < ActiveSupport::TestCase
      URL = "https://example.com/".freeze

      def with_safe_url(&block)
        SafeUrl.stub(:call, ->(url) { url }, &block)
      end

      test "returns parsed metadata from the page" do
        html = '<title>Example</title><meta name="description" content="Hi"><link rel="icon" href="/fav.png">'
        stub_request(:get, URL).to_return(status: 200, body: html, headers: { "Content-Type" => "text/html" })

        result = with_safe_url { Page.fetch(URL) }

        assert_equal "Example", result[:title]
        assert_equal "Hi", result[:description]
        assert_equal "https://example.com/fav.png", result[:favicon_url]
      end

      test "follows a redirect and parses the final page" do
        stub_request(:get, URL).to_return(status: 301, headers: { "Location" => "https://example.com/home" })
        stub_request(:get, "https://example.com/home")
          .to_return(status: 200, body: "<title>Home</title>", headers: { "Content-Type" => "text/html" })

        assert_equal "Home", with_safe_url { Page.fetch(URL) }[:title]
      end

      test "raises Error on a redirect without a Location header" do
        stub_request(:get, URL).to_return(status: 302)
        error = assert_raises(Error) { with_safe_url { Page.fetch(URL) } }
        refute_kind_of TransientError, error
      end

      test "raises Error when there are too many redirects" do
        stub_request(:get, URL).to_return(status: 302, headers: { "Location" => URL })
        assert_raises(Error) { with_safe_url { Page.fetch(URL) } }
      end

      test "raises TransientError on a 500" do
        stub_request(:get, URL).to_return(status: 500)
        assert_raises(TransientError) { with_safe_url { Page.fetch(URL) } }
      end

      test "raises TransientError on a 429" do
        stub_request(:get, URL).to_return(status: 429)
        assert_raises(TransientError) { with_safe_url { Page.fetch(URL) } }
      end

      test "raises TransientError on a timeout" do
        stub_request(:get, URL).to_timeout
        assert_raises(TransientError) { with_safe_url { Page.fetch(URL) } }
      end

      test "raises a non-transient Error on a 404" do
        stub_request(:get, URL).to_return(status: 404)
        error = assert_raises(Error) { with_safe_url { Page.fetch(URL) } }
        refute_kind_of TransientError, error
      end
    end
  end
end
