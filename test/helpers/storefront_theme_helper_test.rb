require "test_helper"

class StorefrontThemeHelperTest < ActionView::TestCase
  test "links the black friday stylesheet only while the window is open" do
    store_settings(:default).update!(black_friday_starts_at: Time.zone.parse("2026-11-27 00:00"),
                                     black_friday_ends_at: Time.zone.parse("2026-12-01 00:00"))

    travel_to Time.zone.parse("2026-11-26 23:59") do
      assert_nil storefront_theme_stylesheet
    end

    travel_to Time.zone.parse("2026-11-28 12:00") do
      assert_match %r{themes/black-friday}, storefront_theme_stylesheet
    end

    travel_to Time.zone.parse("2026-12-01 00:00") do
      assert_nil storefront_theme_stylesheet
    end
  end
end
