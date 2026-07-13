require "test_helper"

class GameOfTheMonthTest < ActiveSupport::TestCase
  test "requires year and month" do
    gotm = GameOfTheMonth.new
    assert_not gotm.valid?
    assert_includes gotm.errors[:year], "não pode ficar em branco"
    assert_includes gotm.errors[:month], "não pode ficar em branco"
  end

  test "rejects pre-2000 years" do
    gotm = GameOfTheMonth.new(year: 1999, month: 1)
    assert_not gotm.valid?
    assert_includes gotm.errors[:year], "deve ser maior ou igual a 2000"
  end

  test "rejects months outside 1..12" do
    [ 0, 13 ].each do |bad|
      gotm = GameOfTheMonth.new(year: 2026, month: bad)
      assert_not gotm.valid?, "expected month=#{bad} to be invalid"
    end
  end

  test "year is unique within a month" do
    GameOfTheMonth.create!(year: 2030, month: 1)
    dup = GameOfTheMonth.new(year: 2030, month: 1)
    assert_not dup.valid?
    assert_includes dup.errors[:year], "já está em uso"
  end

  test "different months in the same year are allowed" do
    GameOfTheMonth.create!(year: 2031, month: 1)
    assert GameOfTheMonth.new(year: 2031, month: 2).valid?
  end

  test "current resolves the row matching today's year/month" do
    assert_equal game_of_the_months(:current_month), GameOfTheMonth.current.first
  end

  test "for_month resolves any historical row" do
    assert_equal game_of_the_months(:past_month), GameOfTheMonth.for_month(2025, 3).first
  end

  test "current is empty when no row matches the current calendar month" do
    GameOfTheMonth.destroy_all
    assert_nil GameOfTheMonth.current.first
  end

  test "destroying a month cascades to picks and brindes" do
    gotm = game_of_the_months(:current_month)
    pick_ids   = gotm.game_of_the_month_product_ids
    brinde_ids = gotm.brinde_ids

    gotm.destroy!

    assert_empty GameOfTheMonthProduct.where(id: pick_ids)
    assert_empty Brinde.where(id: brinde_ids)
  end

  test "products are reachable through the join" do
    gotm = game_of_the_months(:current_month)
    assert_includes gotm.products, products(:yellow)
    assert_includes gotm.products, products(:placeholder)
  end

  test "current_product_ids returns the current edition's product ids" do
    assert_equal game_of_the_months(:current_month).product_ids.sort,
                 GameOfTheMonth.current_product_ids.sort
  end

  test "current_product_ids is empty when there is no current edition" do
    GameOfTheMonth.destroy_all
    assert_empty GameOfTheMonth.current_product_ids
  end

  test "feature_first sorts the featured ids ahead of the rest, by id within each group" do
    featured_ids = [ products(:yellow).id, products(:placeholder).id ]
    ordered = GameOfTheMonth.feature_first(Product.where(id: [
      products(:metroid).id, products(:yellow).id, products(:placeholder).id
    ]), featured_ids)

    featured = [ products(:yellow), products(:placeholder) ].sort_by(&:id)
    assert_equal featured + [ products(:metroid) ], ordered
  end

  test "feature_first leaves plain id order when no ids are featured" do
    ordered = GameOfTheMonth.feature_first(Product.where(id: [ products(:metroid).id, products(:yellow).id ]), [])

    assert_equal [ products(:yellow), products(:metroid) ].sort_by(&:id), ordered
  end
end
