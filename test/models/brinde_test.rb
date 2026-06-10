require "test_helper"

class BrindeTest < ActiveSupport::TestCase
  test "an image is required for the highlight to mean anything" do
    brinde = Brinde.new(game_of_the_month: game_of_the_months(:current_month))
    assert_not brinde.valid?
    assert_includes brinde.errors[:image], "não pode ficar em branco"
  end

  test "with an image attached the record is valid" do
    brinde = Brinde.new(game_of_the_month: game_of_the_months(:current_month))
    brinde.image.attach(
      io: File.open(Rails.root.join("public/images/stores/uploads/2475313/conversions/large.jpg")),
      filename: "brinde.jpg",
      content_type: "image/jpeg"
    )
    assert brinde.valid?
  end

  test "rejects a negative position" do
    brinde = Brinde.new(game_of_the_month: game_of_the_months(:current_month), position: -1)
    assert_not brinde.valid?
  end

  test "weight_grams must be a non-negative integer" do
    brinde = Brinde.new(game_of_the_month: game_of_the_months(:current_month), weight_grams: -1)
    assert_not brinde.valid?

    brinde.weight_grams = 1.5
    assert_not brinde.valid?
  end

  test "in_display_order sorts by position ascending" do
    ordered = game_of_the_months(:current_month).brindes.in_display_order
    assert_equal [ 0, 1 ], ordered.pluck(:position)
  end
end
