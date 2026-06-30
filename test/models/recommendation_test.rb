require "test_helper"

class RecommendationTest < ActiveSupport::TestCase
  test "valid with a url and position" do
    assert Recommendation.new(url: "https://example.com", position: 0).valid?
  end

  test "url is required" do
    recommendation = Recommendation.new(url: "")
    assert_not recommendation.valid?
    assert_includes recommendation.errors[:url], "não pode ficar em branco"
  end

  test "url must be unique" do
    Recommendation.create!(url: "https://example.com")
    dup = Recommendation.new(url: "https://example.com")
    assert_not dup.valid?
    assert_includes dup.errors[:url], "já está em uso"
  end

  test "accepts http and https schemes" do
    assert Recommendation.new(url: "http://example.com").valid?
    assert Recommendation.new(url: "https://example.com").valid?
  end

  test "rejects a non-http scheme" do
    recommendation = Recommendation.new(url: "ftp://example.com")
    assert_not recommendation.valid?
    assert_includes recommendation.errors[:url], "não é válido"
  end

  test "rejects an http url without a host" do
    recommendation = Recommendation.new(url: "http:///path")
    assert_not recommendation.valid?
    assert_includes recommendation.errors[:url], "não é válido"
  end

  test "rejects a malformed url" do
    recommendation = Recommendation.new(url: "http://exa mple")
    assert_not recommendation.valid?
    assert_includes recommendation.errors[:url], "não é válido"
  end

  test "rejects a negative position" do
    assert_not Recommendation.new(url: "https://example.com", position: -1).valid?
  end

  test "is valid without a favicon" do
    recommendation = Recommendation.new(url: "https://example.com")
    assert recommendation.valid?
    assert_nil recommendation.favicon_data_uri
  end

  test "active scope returns only active records" do
    on  = Recommendation.create!(url: "https://a.com", active: true)
    off = Recommendation.create!(url: "https://b.com", active: false)
    assert_includes Recommendation.active, on
    assert_not_includes Recommendation.active, off
  end

  test "in_display_order sorts by position then id" do
    second = Recommendation.create!(url: "https://b.com", position: 2)
    first  = Recommendation.create!(url: "https://a.com", position: 1)
    assert_equal [ first, second ], Recommendation.in_display_order.to_a
  end

  test "display_title returns the title when present" do
    assert_equal "Hello", Recommendation.new(url: "https://example.com", title: "Hello").display_title
  end

  test "display_title falls back to the host when the title is blank" do
    assert_equal "www.example.com", Recommendation.new(url: "https://www.example.com/path").display_title
  end

  test "letter_avatar_initial upcases the first character of the title" do
    assert_equal "H", Recommendation.new(url: "https://e.com", title: "hello").letter_avatar_initial
  end

  test "letter_avatar_initial falls back to the host when the title is blank" do
    assert_equal "E", Recommendation.new(url: "https://example.com").letter_avatar_initial
  end

  test "avatar_gradient returns the stored gradient when present" do
    custom = "linear-gradient(0deg,#000,#fff)"
    assert_equal custom, Recommendation.new(url: "https://e.com", gradient: custom).avatar_gradient
  end

  test "avatar_gradient falls back to the palette by position" do
    assert_equal Recommendation::GRADIENTS[1], Recommendation.new(url: "https://e.com", position: 1).avatar_gradient
  end
end
