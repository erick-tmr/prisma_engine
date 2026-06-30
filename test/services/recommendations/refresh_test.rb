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
      assert_equal "data:image/png;base64,#{Base64.strict_encode64("IMG")}", recommendation.favicon_data_uri
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
      assert_nil recommendation.favicon_data_uri
    end

    test "keeps the existing favicon when a later fetch cannot retrieve one" do
      recommendation = Recommendation.create!(url: PAGE_URL, favicon_data_uri: "data:image/png;base64,OLD=")
      stub_page("<html><head></head></html>")
      stub_request(:get, "https://example.com/favicon.ico").to_return(status: 404)

      with_safe_url { Refresh.call(recommendation) }

      assert_equal "data:image/png;base64,OLD=", recommendation.reload.favicon_data_uri
    end

    test "propagates a page fetch error" do
      recommendation = Recommendation.create!(url: PAGE_URL)
      stub_request(:get, PAGE_URL).to_return(status: 500)

      assert_raises(LinkPreview::Api::TransientError) do
        with_safe_url { Refresh.call(recommendation) }
      end
    end
  end
end
