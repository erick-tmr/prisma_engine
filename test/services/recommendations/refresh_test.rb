require "test_helper"

module Recommendations
  class RefreshTest < ActiveSupport::TestCase
    PAGE_URL = "https://example.com/".freeze
    FAVICON  = "https://example.com/fav.png".freeze

    def with_safe_url(&block)
      LinkPreview::Api::SafeUrl.stub(:call, ->(url) { url }, &block)
    end

    def stub_page(html)
      stub_request(:get, PAGE_URL).to_return(status: 200, body: html, headers: { "Content-Type" => "text/html" })
    end

    def stub_favicon(status: 200)
      stub_request(:get, FAVICON).to_return(status: status, body: "IMG", headers: { "Content-Type" => "image/png" })
    end

    test "fetches title, description and favicon and stamps fetched_at" do
      recommendation = Recommendation.create!(url: PAGE_URL)
      stub_page('<title>Site</title><meta name="description" content="Desc"><link rel="icon" href="/fav.png">')
      stub_favicon

      with_safe_url { Refresh.call(recommendation) }

      recommendation.reload
      assert_equal "Site", recommendation.title
      assert_equal "Desc", recommendation.tagline
      assert recommendation.favicon.attached?
      assert_equal "IMG", recommendation.favicon.download
      assert_equal "image/png", recommendation.favicon.content_type
      assert_equal "favicon.png", recommendation.favicon.filename.to_s
      assert_not_nil recommendation.fetched_at
    end

    test "keeps the existing title and tagline when the page omits them" do
      recommendation = Recommendation.create!(url: PAGE_URL, title: "Antigo", tagline: "Velho")
      stub_page("<html><head></head></html>")
      stub_request(:get, "https://example.com/favicon.ico")
        .to_return(status: 200, body: "IMG", headers: { "Content-Type" => "image/x-icon" })

      with_safe_url { Refresh.call(recommendation) }

      recommendation.reload
      assert_equal "Antigo", recommendation.title
      assert_equal "Velho", recommendation.tagline
    end

    test "saves the record without a favicon when the favicon fetch fails" do
      recommendation = Recommendation.create!(url: PAGE_URL)
      stub_page('<title>Site</title><link rel="icon" href="/fav.png">')
      stub_favicon(status: 404)

      with_safe_url { Refresh.call(recommendation) }

      recommendation.reload
      assert_equal "Site", recommendation.title
      assert_not recommendation.favicon.attached?
    end

    test "keeps the existing favicon when a later fetch cannot retrieve one" do
      recommendation = Recommendation.create!(url: PAGE_URL)
      recommendation.favicon.attach(io: StringIO.new("OLD"), filename: "favicon.png", content_type: "image/png")
      stub_page("<html><head></head></html>")
      stub_request(:get, "https://example.com/favicon.ico").to_return(status: 404)

      with_safe_url { Refresh.call(recommendation) }

      assert_equal "OLD", recommendation.reload.favicon.download
    end

    test "propagates a page fetch error" do
      recommendation = Recommendation.create!(url: PAGE_URL)
      stub_request(:get, PAGE_URL).to_return(status: 500)

      assert_raises(LinkPreview::Api::TransientError) do
        with_safe_url { Refresh.call(recommendation) }
      end
    end

    test "call_all refreshes every recommendation" do
      recommendation = Recommendation.create!(url: PAGE_URL, position: 0)
      stub_page('<title>Site</title><link rel="icon" href="/fav.png">')
      stub_favicon

      with_safe_url { Refresh.call_all }

      assert_equal "Site", recommendation.reload.title
    end

    test "call_all logs and continues when one recommendation fails" do
      good = Recommendation.create!(url: PAGE_URL, position: 0)
      Recommendation.create!(url: "https://bad.example/", position: 1)
      stub_page('<title>Bom</title><link rel="icon" href="/fav.png">')
      stub_favicon
      stub_request(:get, "https://bad.example/").to_return(status: 500)

      with_safe_url { Refresh.call_all }

      assert_equal "Bom", good.reload.title
    end
  end
end
