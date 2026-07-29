class PublishScheduledGameOfTheMonthJob < ApplicationJob
  def perform
    Catalog::PublishScheduledEditions.call
  end
end
