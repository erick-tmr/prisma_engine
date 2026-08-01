require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "reads a distance in the past as pt-BR" do
    assert_equal "há 2 dias", relative_time_ago(2.days.ago)
    assert_equal "há 1 dia", relative_time_ago(1.day.ago)
  end

  test "falls back to the coarse buckets for very recent and very old timestamps" do
    assert_equal "há menos de um minuto", relative_time_ago(10.seconds.ago)
    assert_equal "há 3 meses", relative_time_ago(92.days.ago)
  end
end
