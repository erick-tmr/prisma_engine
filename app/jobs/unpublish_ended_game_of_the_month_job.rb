class UnpublishEndedGameOfTheMonthJob < ApplicationJob
  def perform
    previous_month = 1.month.ago
    ended = GameOfTheMonth.for_month(previous_month.year, previous_month.month).first
    return if ended.nil?

    ended.products.update_all(published: false)
  end
end
