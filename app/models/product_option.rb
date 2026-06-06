class ProductOption < ApplicationRecord
  include HasMoney

  belongs_to :product

  validates :name, presence: true, uniqueness: { scope: [ :product_id, :group_name ] }
  validates :price_delta_cents, numericality: { only_integer: true }

  money_attribute :price_delta_cents, as: :price_delta_formatted

  scope :in_display_order, -> { order(:position) }
end
