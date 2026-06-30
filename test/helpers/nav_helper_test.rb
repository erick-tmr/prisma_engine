require "test_helper"

class NavHelperTest < ActionView::TestCase
  test "nav_recommendations returns active recommendations in display order" do
    second = Recommendation.create!(url: "https://b.com", position: 2, active: true)
    first  = Recommendation.create!(url: "https://a.com", position: 1, active: true)
    Recommendation.create!(url: "https://c.com", position: 0, active: false)

    assert_equal [ first, second ], nav_recommendations.to_a
  end

  test "social_links returns the configured hash" do
    assert_equal "https://wa.me/5535920001100", social_links[:whatsapp]
    assert_equal "https://instagram.com/prisma.games", social_links[:instagram]
  end
end
