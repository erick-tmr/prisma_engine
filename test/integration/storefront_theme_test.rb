require "test_helper"

class StorefrontThemeTest < ActionDispatch::IntegrationTest
  test "the storefront uses its regular look outside the black friday window" do
    get root_path

    assert_response :success
    assert_select "link[href*=?]", "themes/black-friday", count: 0
  end

  test "the storefront loads the black friday stylesheet last while the window is open" do
    store_settings(:default).update!(black_friday_starts_at: 1.hour.ago, black_friday_ends_at: 1.hour.from_now)

    get root_path

    assert_select "head link[rel=stylesheet]:last-of-type[href*=?]", "themes/black-friday"
  end
end
