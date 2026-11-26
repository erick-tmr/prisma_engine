require "test_helper"

module Admin
  class StoreThemeHelperTest < ActionView::TestCase
    test "the picker shows the time to the minute in Brasília time" do
      assert_equal "2026-11-27T00:00", theme_picker_value(Time.utc(2026, 11, 27, 3, 0, 40))
    end

    test "an empty window leaves the picker blank" do
      assert_nil theme_picker_value(nil)
    end
  end
end
