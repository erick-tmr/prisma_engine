require "test_helper"

class PublishGameOfTheMonthJobTest < ActiveJob::TestCase
  test "publishes the products of the edition it was booked for" do
    edition = staged_edition

    PublishGameOfTheMonthJob.perform_now(edition.id)

    assert products(:hidden).reload.published
    assert_not_nil edition.reload.published_at
  end

  test "does nothing when the edition was deleted before the job ran" do
    edition = staged_edition
    edition.destroy!

    PublishGameOfTheMonthJob.perform_now(edition.id)

    assert_not products(:hidden).reload.published
  end

  test "does nothing when the edition already went live" do
    edition = staged_edition
    Catalog::PublishEdition.call(edition)
    stamped = edition.reload.published_at

    PublishGameOfTheMonthJob.perform_now(edition.id)

    assert_equal stamped, edition.reload.published_at
  end

  test "a booking left over from an earlier time no-ops when the edition was pushed back" do
    edition = staged_edition
    later = 1.month.from_now
    edition.update!(year: later.year, month: later.month, publish_at: later.beginning_of_month)

    PublishGameOfTheMonthJob.perform_now(edition.id)

    assert_not products(:hidden).reload.published
    assert_nil edition.reload.published_at
  end

  private

  def staged_edition
    GameOfTheMonth.for_current_month.destroy_all
    GameOfTheMonth.create!(
      year: Time.current.year, month: Time.current.month, publish_at: Time.current.beginning_of_month
    ).tap { |edition| edition.products << products(:hidden) }
  end
end
