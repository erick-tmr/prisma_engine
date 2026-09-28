class ReturnFreightCharge < ApplicationRecord
  TTL = 3.days

  belongs_to :shipment

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :expires_at, presence: true

  scope :live, -> { where(voided_at: nil) }
  scope :newest_first, -> { order(id: :desc) }

  def self.issue(shipment:, amount_cents:, at: Time.current)
    shipment.return_freight_charges.create!(amount_cents: amount_cents, created_at: at, expires_at: at + TTL)
  end

  def paid?
    paid_at.present?
  end

  def expired?
    !paid? && expires_at <= Time.current
  end

  def pending?
    !paid? && !expired?
  end

  def state
    return "paid" if paid?

    expired? ? "expired" : "pending"
  end
end
