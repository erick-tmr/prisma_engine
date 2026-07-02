class Brinde < ApplicationRecord
  belongs_to :game_of_the_month_product
  has_one :game_of_the_month, through: :game_of_the_month_product

  has_one_attached :image

  validates :image, presence: true
  validates :position,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :weight_grams,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :in_display_order, -> { order(:position, :id) }
end
