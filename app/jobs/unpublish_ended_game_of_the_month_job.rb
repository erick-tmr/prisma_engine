class UnpublishEndedGameOfTheMonthJob < ApplicationJob
  def perform
    previous_month = 1.month.ago
    ended = GameOfTheMonth.for_month(previous_month.year, previous_month.month).first
    return if ended.nil?

    ended.products
         .where.not(id: carried_over_product_ids)
         .update_all(published: false, updated_at: Time.current)
  end

  private

  def carried_over_product_ids
    GameOfTheMonth.current.first&.product_ids || []
  end
end
