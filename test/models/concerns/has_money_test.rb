require "test_helper"

class HasMoneyTest < ActiveSupport::TestCase
  test "formats cents as pt-BR currency" do
    assert_equal "R$ 190.00", HasMoney.format(19_000)
  end

  test "parses pt-BR money strings into cents" do
    assert_equal 19_000, HasMoney.parse("190,00")
    assert_equal 123_450, HasMoney.parse("1.234,50")
    assert_equal 2_000, HasMoney.parse("20")
    assert_equal 21_000, HasMoney.parse("R$ 210,00")
  end

  test "treats blank or symbol-only input as zero" do
    assert_equal 0, HasMoney.parse("")
    assert_equal 0, HasMoney.parse(nil)
    assert_equal 0, HasMoney.parse("R$")
  end
end
