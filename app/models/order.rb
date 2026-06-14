class Order < ApplicationRecord
  InvalidTransition = Class.new(StandardError)
  UnallocatableNumber = Class.new(StandardError)

  NUMBER_ATTEMPTS = 10
  EXPIRY_WINDOW = 24.hours

  belongs_to :user
  has_many :order_items, dependent: :destroy
  accepts_nested_attributes_for :order_items

  has_secure_token :webhook_token

  STATUSES = %w[
    awaiting_payment
    payment_confirmed
    awaiting_components
    in_production
    production_issue
    label_issued
    shipped
    delivered
    cancelled
  ].freeze

  enum :status, STATUSES.index_with(&:itself), default: "awaiting_payment", validate: true

  TRANSITIONS = {
    "awaiting_payment"    => %w[payment_confirmed cancelled],
    "payment_confirmed"   => %w[awaiting_components in_production],
    "awaiting_components" => %w[in_production],
    "in_production"       => %w[label_issued production_issue],
    "production_issue"    => %w[in_production],
    "label_issued"        => %w[shipped],
    "shipped"             => %w[delivered],
    "delivered"           => [],
    "cancelled"           => %w[payment_confirmed]
  }.freeze

  CANCELLABLE_STATUSES = %w[awaiting_payment payment_confirmed].freeze

  scope :awaiting_payment_expired, -> { awaiting_payment.where(created_at: ..EXPIRY_WINDOW.ago) }

  validates :number, presence: true, uniqueness: true
  validates :subtotal_cents, :shipping_cents, :total_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :shipping_service, inclusion: { in: Shipping::SERVICES.keys.map(&:to_s) }

  before_validation :assign_number, on: :create

  def placed_at
    created_at
  end

  def shipping_address
    {
      recipient: ship_receiver_name, cpf: ship_receiver_cpf,
      street: ship_street, number: ship_number, complement: ship_complement,
      neighborhood: ship_neighborhood, city: ship_city, state: ship_state, zip: ship_zip
    }
  end

  def cancellable?
    CANCELLABLE_STATUSES.include?(status)
  end

  def transition_to!(next_status)
    target = next_status.to_s
    raise InvalidTransition, "#{status} → #{target}" unless TRANSITIONS.fetch(status).include?(target)

    update!(status: target)
  end

  def confirm_payment!
    transition_to!("payment_confirmed")
  end

  def cancel!
    transition_to!("cancelled")
  end

  def payment_deadline
    created_at + EXPIRY_WINDOW
  end

  def payment_expired?
    awaiting_payment? && payment_deadline.past?
  end

  private

  def assign_number
    return if number.present?

    self.number = generate_unique_number
  end

  def generate_unique_number
    NUMBER_ATTEMPTS.times do
      candidate = "PG-#{Time.current.strftime('%Y%m%d')}#{format('%04d', rand(10_000))}"
      return candidate unless self.class.exists?(number: candidate)
    end
    raise UnallocatableNumber
  end
end
