class ProductOption < ApplicationRecord
  belongs_to :product

  validates :name, presence: true, uniqueness: { scope: [ :product_id, :group_name ] }
  validates :weight_delta_grams,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :in_display_order, -> { order(:position) }
end
