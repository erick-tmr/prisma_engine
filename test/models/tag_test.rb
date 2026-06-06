require "test_helper"

class TagTest < ActiveSupport::TestCase
  test "products are reachable through the join" do
    assert_includes tags(:pokemon).products, products(:yellow)
  end

  test "slug is generated from the name" do
    tag = Tag.create!(name: "rtc")
    assert_equal "rtc", tag.slug
  end
end
