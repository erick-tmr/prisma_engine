class ProductPhoto < ApplicationRecord
  belongs_to :product

  has_one_attached :image

  scope :in_display_order, -> { order(:position) }
end
