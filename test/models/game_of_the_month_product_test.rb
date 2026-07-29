require "test_helper"

class GameOfTheMonthProductTest < ActiveSupport::TestCase
  test "a product can only be picked once per month" do
    gotm = game_of_the_months(:current_month)
    dup  = GameOfTheMonthProduct.new(
      game_of_the_month: gotm,
      product: products(:yellow)
    )
    assert_not dup.valid?
    assert_includes dup.errors[:product_id], "já está em uso"
  end

  test "the same product can headline different months" do
    pick = GameOfTheMonthProduct.new(
      game_of_the_month: game_of_the_months(:past_month),
      product: products(:yellow)
    )
    assert pick.valid?
  end

  test "rejects a negative position" do
    pick = GameOfTheMonthProduct.new(
      game_of_the_month: game_of_the_months(:past_month),
      product: products(:yellow),
      position: -1
    )
    assert_not pick.valid?
  end

  test "in_display_order sorts by position ascending" do
    ordered = game_of_the_months(:current_month).game_of_the_month_products.in_display_order
    assert_equal [ 0, 1, 2 ], ordered.pluck(:position)
  end
end
