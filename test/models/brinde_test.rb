require "test_helper"

class BrindeTest < ActiveSupport::TestCase
  test "an image is required for the highlight to mean anything" do
    brinde = Brinde.new(game_of_the_month_product: game_of_the_month_products(:current_pokemon_yellow))
    assert_not brinde.valid?
    assert_includes brinde.errors[:image], "não pode ficar em branco"
  end

  test "with an image attached the record is valid" do
    brinde = Brinde.new(game_of_the_month_product: game_of_the_month_products(:current_pokemon_yellow))
    brinde.image.attach(
      io: File.open(file_fixture("sample_product.jpg")),
      filename: "brinde.jpg",
      content_type: "image/jpeg"
    )
    assert brinde.valid?
  end

  test "rejects a negative position" do
    brinde = Brinde.new(game_of_the_month_product: game_of_the_month_products(:current_pokemon_yellow), position: -1)
    assert_not brinde.valid?
  end

  test "weight_grams must be a non-negative integer" do
    brinde = Brinde.new(game_of_the_month_product: game_of_the_month_products(:current_pokemon_yellow), weight_grams: -1)
    assert_not brinde.valid?

    brinde.weight_grams = 1.5
    assert_not brinde.valid?
  end

  test "in_display_order sorts by position ascending" do
    ordered = game_of_the_months(:current_month).brindes.in_display_order
    assert_equal [ 0, 1 ], ordered.pluck(:position)
  end
end
