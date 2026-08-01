class UnpublishEndedGameOfTheMonthJob < ApplicationJob
  def perform
    previous_month = 1.month.ago
    ended = GameOfTheMonth.for_month(previous_month.year, previous_month.month).first
    return if ended.nil?

    dropped = ended.products.where.not(id: carried_over_product_ids)
    product_ids = dropped.ids
    dropped.update_all(published: false, updated_at: Time.current)
    SyncGameOfTheMonthCatalogJob.perform_later(product_ids)
  end

  private

  def carried_over_product_ids
    GameOfTheMonth.for_current_month.first&.product_ids || []
  end
end
