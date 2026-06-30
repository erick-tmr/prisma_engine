require "test_helper"

module LinkPreview
  module Api
    class MetadataTest < ActiveSupport::TestCase
      BASE = "https://example.com/page".freeze

      test "reads and strips the title from the <title> element" do
        result = Metadata.parse("<html><head><title>  Hello  </title></head></html>", base_url: BASE)
        assert_equal "Hello", result[:title]
      end

      test "falls back to og:title when there is no <title>" do
        html = '<meta property="og:title" content="OG Title">'
        assert_equal "OG Title", Metadata.parse(html, base_url: BASE)[:title]
      end

      test "title is nil when neither title nor og:title is present" do
        assert_nil Metadata.parse("<html><head></head></html>", base_url: BASE)[:title]
      end

      test "reads the description from meta[name=description]" do
        html = '<meta name="description" content="A desc">'
        assert_equal "A desc", Metadata.parse(html, base_url: BASE)[:description]
      end

      test "falls back to og:description" do
        html = '<meta property="og:description" content="OG desc">'
        assert_equal "OG desc", Metadata.parse(html, base_url: BASE)[:description]
      end

      test "description is nil when absent" do
        assert_nil Metadata.parse("<html></html>", base_url: BASE)[:description]
      end

      test "prefers the apple-touch-icon for the favicon" do
        html = '<link rel="icon" href="/icon.png"><link rel="apple-touch-icon" href="/apple.png">'
        assert_equal "https://example.com/apple.png", Metadata.parse(html, base_url: BASE)[:favicon_url]
      end

      test "uses a shortcut icon link when there is no apple-touch-icon" do
        html = '<link rel="shortcut icon" href="/fav.ico">'
        assert_equal "https://example.com/fav.ico", Metadata.parse(html, base_url: BASE)[:favicon_url]
      end

      test "falls back to /favicon.ico when no icon link exists" do
        assert_equal "https://example.com/favicon.ico", Metadata.parse("<html></html>", base_url: BASE)[:favicon_url]
      end

      test "resolves an absolute favicon URL from a relative href" do
        html = '<link rel="icon" href="../assets/fav.png">'
        assert_equal "https://example.com/assets/fav.png", Metadata.parse(html, base_url: BASE)[:favicon_url]
      end

      test "passes a data: URI favicon through untouched" do
        data = "data:image/svg+xml,%3Csvg xmlns='x'%3E%3C/svg%3E"
        html = %(<link rel="icon" href="#{data}">)
        assert_equal data, Metadata.parse(html, base_url: BASE)[:favicon_url]
      end

      test "falls back to /favicon.ico when the icon href is unparseable" do
        html = '<link rel="icon" href="/has space.png">'
        assert_equal "https://example.com/favicon.ico", Metadata.parse(html, base_url: BASE)[:favicon_url]
      end
    end
  end
end
