require "test_helper"

module Catalog
  class PublishScheduledEditionsTest < ActiveSupport::TestCase
    test "publishes the products of a due edition and stamps published_at" do
      edition = due_edition

      Catalog::PublishScheduledEditions.call

      assert products(:hidden).reload.published
      assert_not_nil edition.reload.published_at
    end

    test "bumps updated_at so the cached home band is rebuilt" do
      due_edition
      products(:hidden).update_column(:updated_at, 1.hour.ago)

      Catalog::PublishScheduledEditions.call

      assert_operator products(:hidden).reload.updated_at, :>, 1.minute.ago
    end

    test "a second run keeps the original stamp and touches nothing else" do
      edition = due_edition
      Catalog::PublishScheduledEditions.call
      stamped = edition.reload.published_at

      Catalog::PublishScheduledEditions.call

      assert_equal stamped, edition.reload.published_at
      assert_not products(:staged).reload.published
    end

    test "leaves an edition scheduled for later alone" do
      edition = GameOfTheMonth.create!(year: 2031, month: 8, publish_at: 1.minute.from_now)
      edition.products << products(:hidden)

      Catalog::PublishScheduledEditions.call

      assert_not products(:hidden).reload.published
      assert_nil edition.reload.published_at
    end

    private

    def due_edition
      GameOfTheMonth.create!(year: 2031, month: 8, publish_at: 1.minute.ago).tap do |edition|
        edition.products << products(:hidden)
      end
    end
  end
end
