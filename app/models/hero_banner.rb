class HeroBanner < ApplicationRecord
  has_one_attached :image

  validates :image, presence: true
  validates :position,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }
  scope :in_display_order, -> { order(:position, :id) }
end
