require "test_helper"

class PublishScheduledGameOfTheMonthJobTest < ActiveJob::TestCase
  test "publishes the products of an edition whose scheduled time has passed" do
    edition = GameOfTheMonth.create!(year: 2031, month: 8, publish_at: 1.minute.ago)
    edition.products << products(:hidden)

    PublishScheduledGameOfTheMonthJob.perform_now

    assert products(:hidden).reload.published
    assert_not_nil edition.reload.published_at
  end

  test "does nothing when no edition is due" do
    PublishScheduledGameOfTheMonthJob.perform_now

    assert_not products(:staged).reload.published
    assert_not products(:hidden).reload.published
  end
end
