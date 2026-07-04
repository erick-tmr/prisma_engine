class Order < ApplicationRecord
  InvalidTransition = Class.new(StandardError)
  UnallocatableNumber = Class.new(StandardError)

  NUMBER_ATTEMPTS = 10
  EXPIRY_WINDOW = 24.hours

  belongs_to :user
  belongs_to :production_batch, optional: true
  has_one :shipment, dependent: :nullify
  has_one :shipping_label, through: :shipment
  has_many :order_items, dependent: :destroy
  has_many :payment_webhook_events, dependent: :destroy
  has_many :status_changes, class_name: "OrderStatusChange", dependent: :destroy
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
    delivery_issue
    awaiting_refund
    cancelled
  ].freeze

  enum :status, STATUSES.index_with(&:itself), default: "awaiting_payment", validate: true

  TRANSITIONS = {
    "awaiting_payment"    => %w[payment_confirmed cancelled],
    "payment_confirmed"   => %w[awaiting_components in_production awaiting_refund],
    "awaiting_components" => %w[in_production awaiting_refund],
    "in_production"       => %w[label_issued production_issue],
    "production_issue"    => %w[in_production],
    "label_issued"        => %w[shipped],
    "shipped"             => %w[delivered delivery_issue],
    "delivered"           => [],
    "delivery_issue"      => %w[awaiting_refund shipped cancelled],
    "awaiting_refund"     => %w[cancelled],
    "cancelled"           => %w[payment_confirmed]
  }.freeze

  CANCELLABLE_STATUSES = %w[awaiting_payment payment_confirmed awaiting_components].freeze

  scope :awaiting_payment_expired, -> { awaiting_payment.where(created_at: ..EXPIRY_WINDOW.ago) }
  scope :recent_first, -> { order(created_at: :desc) }

  validates :number, presence: true, uniqueness: true
  validates :subtotal_cents, :total_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  normalizes :observation, with: ->(value) { value.strip.presence }

  before_validation :assign_number, on: :create
  after_create :record_initial_status
  before_destroy :prevent_destroy

  def to_param
    number
  end

  def placed_at
    created_at
  end

  def payment_status
    awaiting_payment? || cancelled? ? :pending : :paid
  end

  def tracking_events
    shipment ? shipment.tracking_events.order(:position) : []
  end

  def shipping_visible?
    tracking_events.any?
  end

  def cancellable?
    CANCELLABLE_STATUSES.include?(status)
  end

  # :reek:BooleanParameter — `automatic` distinguishes system-driven transitions
  # (webhook, Correios, expiry) from operator moves; a flag is the clean shape here.
  def transition_to!(next_status, actor: nil, automatic: false)
    target = next_status.to_s
    raise InvalidTransition, "#{status} → #{target}" unless TRANSITIONS.fetch(status).include?(target)

    previous = status
    transaction do
      update!(status: target)
      status_changes.create!(from_status: previous, to_status: target, actor: actor, automatic: automatic)
    end
  end

  def confirm_payment!(**opts)
    transition_to!("payment_confirmed", **opts)
  end

  def advance_to_label_issued!(**opts)
    transition_to!("label_issued", **opts) unless label_issued?
  end

  def cancel!(**opts)
    transition_to!("cancelled", **opts)
  end

  def request_refund!(**opts)
    transition_to!("awaiting_refund", **opts)
  end

  def cancel_by_customer!(**opts)
    awaiting_payment? ? cancel!(**opts) : request_refund!(**opts)
  end

  def payment_deadline
    created_at + EXPIRY_WINDOW
  end

  def payment_expired?
    awaiting_payment? && payment_deadline.past?
  end

  private

  def record_initial_status
    status_changes.create!(from_status: nil, to_status: status, automatic: true)
  end

  def prevent_destroy
    errors.add(:base, "Orders are kept for history and cannot be deleted; cancel instead.")
    throw :abort
  end

  def assign_number
    return if number.present?

    self.number = generate_unique_number
  end

  def generate_unique_number
    NUMBER_ATTEMPTS.times do
      candidate = "PG-#{format('%05d', rand(100_000))}"
      return candidate unless self.class.exists?(number: candidate)
    end
    raise UnallocatableNumber
  end
end
