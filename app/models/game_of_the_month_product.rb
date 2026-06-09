class GameOfTheMonthProduct < ApplicationRecord
  belongs_to :game_of_the_month
  belongs_to :product

  validates :product_id, uniqueness: { scope: :game_of_the_month_id }
  validates :position,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :in_display_order, -> { order(:position, :id) }
end
