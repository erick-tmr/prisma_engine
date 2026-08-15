class Order < ApplicationRecord
  InvalidTransition = Class.new(StandardError)
  UnallocatableNumber = Class.new(StandardError)

  NUMBER_ATTEMPTS = 10
  EXPIRY_WINDOW = 24.hours

  OBSERVATION_LIMIT = 280
  OBSERVATION_STORAGE_LIMIT = OBSERVATION_LIMIT * 5

  belongs_to :user
  belongs_to :production_batch, optional: true
  belongs_to :merged_into, class_name: "Order", optional: true
  has_one :shipment, -> { where(direction: :outbound) },
          inverse_of: :order, dependent: :nullify
  has_one :return_shipment, -> { where(direction: :inbound) },
          class_name: "Shipment", inverse_of: :order, dependent: :destroy
  has_one :shipping_label, through: :shipment
  has_one :return_shipping_label, through: :return_shipment, source: :shipping_label
  has_one :order_merge, foreign_key: :carrier_order_id, inverse_of: :carrier_order, dependent: :destroy
  has_many :order_items, dependent: :destroy
  has_many :merged_orders, class_name: "Order", foreign_key: :merged_into_id, dependent: :nullify
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
    awaiting_return
    returning
    returned
    cancelled
    merged
  ].freeze

  enum :status, STATUSES.index_with(&:itself), default: "awaiting_payment", validate: true

  TRANSITIONS = {
    "awaiting_payment"    => %w[payment_confirmed cancelled],
    "payment_confirmed"   => %w[awaiting_components in_production merged cancelled],
    "awaiting_components" => %w[in_production merged cancelled],
    "in_production"       => %w[label_issued production_issue cancelled],
    "production_issue"    => %w[in_production merged cancelled],
    "label_issued"        => %w[shipped cancelled],
    "shipped"             => %w[delivered delivery_issue returned],
    "delivered"           => %w[awaiting_return returned],
    "delivery_issue"      => %w[delivered awaiting_return returned shipped],
    "awaiting_return"     => %w[returning returned delivered],
    "returning"           => %w[returned delivered],
    "returned"            => %w[shipped cancelled],
    "cancelled"           => %w[payment_confirmed],
    "merged"              => []
  }.freeze

  CANCELLABLE_STATUSES = TRANSITIONS.select { |_, targets| targets.include?("cancelled") }.keys.freeze
  MERGEABLE_STATUSES = Production::EligibleOrders::STATUSES
  PAID_STATUSES = (STATUSES - %w[awaiting_payment cancelled merged]).freeze

  scope :awaiting_payment_expired, -> { awaiting_payment.where(created_at: ..EXPIRY_WINDOW.ago) }
  scope :recent_first, -> { order(created_at: :desc) }
  scope :mergeable, -> { where(status: MERGEABLE_STATUSES).order(created_at: :asc) }
  scope :paid, -> { where(status: PAID_STATUSES) }

  validates :number, presence: true, uniqueness: true
  validates :subtotal_cents, :total_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :observation, length: { maximum: OBSERVATION_LIMIT }, on: :create

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
    unpaid? ? :pending : :paid
  end

  def unpaid?
    awaiting_payment? || (cancelled? && !ever_confirmed?)
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

  # :reek:BooleanParameter
  def transition_to!(next_status, actor: nil, automatic: false)
    target = next_status.to_s
    previous = status
    raise InvalidTransition, "#{previous} → #{target}" unless TRANSITIONS.fetch(previous).include?(target)

    transaction do
      claim_status(previous, target) &&
        status_changes.create!(from_status: previous, to_status: target, actor: actor, automatic: automatic).present?
    end
  end

  def confirm_payment!(**opts)
    transition_to!("payment_confirmed", **opts)
  end

  def advance_to_label_issued!(**opts)
    transition_to!("label_issued", **opts) if shippable? && !label_issued?
  end

  def shippable?
    !cancelled?
  end

  def cancel!(**opts)
    transition_to!("cancelled", **opts)
  end

  def payment_deadline
    created_at + EXPIRY_WINDOW
  end

  def payment_expired?
    awaiting_payment? && payment_deadline.past?
  end

  def assign_number
    return if number.present?

    self.number = generate_unique_number
  end

  private

  def ever_confirmed?
    status_changes.exists?(to_status: "payment_confirmed")
  end

  def claim_status(previous, target)
    claimed = self.class.where(id: id, status: previous).update_all(status: target, updated_at: Time.current)
    reload
    claimed == 1
  end

  def record_initial_status
    status_changes.create!(from_status: nil, to_status: status, automatic: true)
  end

  def prevent_destroy
    errors.add(:base, "Orders are kept for history and cannot be deleted; cancel instead.")
    throw :abort
  end

  def generate_unique_number
    NUMBER_ATTEMPTS.times do
      candidate = "PG-#{format('%05d', rand(100_000))}"
      return candidate unless self.class.exists?(number: candidate)
    end
    raise UnallocatableNumber
  end
end
