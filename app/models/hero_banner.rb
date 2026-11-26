class HeroBanner < ApplicationRecord
  has_one_attached :image

  validates :image, presence: true
  validates :position,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }
  scope :in_display_order, -> { order(:position, :id) }
  scope :showable, -> { active.in_display_order.with_attached_image }

  def self.for_home
    showable.where(black_friday: false)
  end

  def self.for_black_friday_home
    seasonal = showable.where(black_friday: true)
    seasonal.exists? ? seasonal : for_home
  end
end
