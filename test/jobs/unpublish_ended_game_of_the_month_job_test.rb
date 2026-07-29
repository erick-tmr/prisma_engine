require "test_helper"

class UnpublishEndedGameOfTheMonthJobTest < ActiveJob::TestCase
  test "unpublishes the products of the month that just ended" do
    previous_month = 1.month.ago
    ended = GameOfTheMonth.create!(year: previous_month.year, month: previous_month.month, note: "Especial Metroid")
    ended.products << products(:metroid)
    products(:metroid).update!(published: true)

    UnpublishEndedGameOfTheMonthJob.perform_now

    assert_not products(:metroid).reload.published
    assert products(:yellow).reload.published
    assert products(:placeholder).reload.published
  end

  test "does nothing when no edition exists for the prior month" do
    UnpublishEndedGameOfTheMonthJob.perform_now

    assert products(:yellow).reload.published
    assert products(:placeholder).reload.published
  end

  test "unpublishes everything when no edition follows the one that ended" do
    previous_month = 1.month.ago
    ended = GameOfTheMonth.create!(year: previous_month.year, month: previous_month.month, note: "Especial Metroid")
    ended.products << products(:metroid)
    game_of_the_months(:current_month).destroy!

    UnpublishEndedGameOfTheMonthJob.perform_now

    assert_not products(:metroid).reload.published
  end

  test "keeps a product that carries over into the incoming edition" do
    previous_month = 1.month.ago
    ended = GameOfTheMonth.create!(year: previous_month.year, month: previous_month.month, note: "Especial Metroid")
    ended.products << products(:yellow) << products(:metroid)

    UnpublishEndedGameOfTheMonthJob.perform_now

    assert products(:yellow).reload.published
    assert_not products(:metroid).reload.published
  end
end
