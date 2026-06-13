class OrderItem < ApplicationRecord
  belongs_to :order
  # Optional: the catalog row is a convenience link, not the source of truth. It
  # nullifies if the product is later deleted; the snapshot below stands alone.
  belongs_to :product, optional: true

  validates :name, presence: true
  validates :unit_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }

  # Snapshot total in cents; mirrors Cart::Line#line_total_cents and
  # Account::MockOrderItem#line_total_cents.
  def line_total_cents
    unit_price_cents * quantity
  end
end
