class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product, optional: true

  validates :name, presence: true
  validates :unit_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }

  normalizes :requested_game, :request_notes, with: ->(value) { value.strip.presence }

  def line_total_cents
    unit_price_cents * quantity
  end

  def custom_order?
    requested_game.present?
  end
end
