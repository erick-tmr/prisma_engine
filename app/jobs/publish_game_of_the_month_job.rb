class PublishGameOfTheMonthJob < ApplicationJob
  def perform(edition_id)
    edition = GameOfTheMonth.find_by(id: edition_id)
    return if edition.nil? || edition.published_at.present? || edition.publish_at.future?

    Catalog::PublishEdition.call(edition)
  end
end
