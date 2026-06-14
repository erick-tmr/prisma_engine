require "test_helper"

class GameOfTheMonthHelperTest < ActionView::TestCase
  test "gotm_month_name returns the pt-BR name for a 1..12 month" do
    assert_equal "Janeiro", gotm_month_name(1)
    assert_equal "Junho", gotm_month_name(6)
    assert_equal "Dezembro", gotm_month_name(12)
  end
end
