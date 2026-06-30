require "test_helper"

class RefreshRecommendationsJobTest < ActiveJob::TestCase
  test "refreshes every recommendation's title, tagline and favicon" do
    recommendation = Recommendation.create!(url: "https://example.com/")
    stub_request(:get, "https://example.com/").to_return(
      status: 200,
      body: '<title>Site</title><meta name="description" content="Desc"><link rel="icon" href="/fav.png">',
      headers: { "Content-Type" => "text/html" }
    )
    stub_request(:get, "https://example.com/fav.png")
      .to_return(status: 200, body: "IMG", headers: { "Content-Type" => "image/png" })

    LinkPreview::Api::SafeUrl.stub(:call, ->(url) { url }) do
      RefreshRecommendationsJob.perform_now
    end

    recommendation.reload
    assert_equal "Site", recommendation.title
    assert_equal "Desc", recommendation.tagline
    assert recommendation.favicon_data_uri.present?
  end
end
