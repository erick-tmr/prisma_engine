require "test_helper"

module Catalog
  class PublishEditionTest < ActiveSupport::TestCase
    test "publishes every product of the edition and stamps it" do
      edition = staged_edition

      Catalog::PublishEdition.call(edition)

      assert products(:hidden).reload.published
      assert_not_nil edition.reload.published_at
    end

    test "bumps updated_at so the cached home band is rebuilt" do
      edition = staged_edition
      products(:hidden).update_column(:updated_at, 1.hour.ago)

      Catalog::PublishEdition.call(edition)

      assert_operator products(:hidden).reload.updated_at, :>, 1.minute.ago
    end

    test "clears the booking id once the edition is live" do
      edition = staged_edition
      assert edition.reload.publish_job_id.present?

      Catalog::PublishEdition.call(edition)

      assert_nil edition.reload.publish_job_id
    end

    test "leaves the rest of the catalog alone" do
      Catalog::PublishEdition.call(staged_edition)

      assert_not products(:staged).reload.published
    end

    private

    def staged_edition
      GameOfTheMonth.create!(year: 2031, month: 8, publish_at: 1.minute.ago).tap do |edition|
        edition.products << products(:hidden)
      end
    end
  end
end
