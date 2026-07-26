class Shipment < ApplicationRecord
  CORREIOS_STATUSES = {
    1 => :preatendido,
    2 => :prepostado,
    3 => :postado,
    4 => :expirado,
    5 => :cancelado,
    6 => :estornado,
    7 => :pendente
  }.freeze

  enum :tracking_state,
       { pending: 0, in_transit: 1, delivered: 2, returned: 3, unavailable: 4 },
       prefix: :tracking

  FINAL_TRACKING_STATES = %w[delivered returned unavailable].freeze

  TERMINAL_PREPOST_STATUSES = [ 4, 5, 6 ].freeze

  RECEIVER_OBS_LIMIT = 100

  TRACKING_URL = "https://rastreamento.correios.com.br/app/index.php".freeze

  belongs_to :order

  has_one :shipping_label, dependent: :destroy

  has_many :tracking_events,
           class_name: "ShipmentTrackingEvent",
           dependent: :destroy

  validates :tracking_code, uniqueness: true, allow_nil: true
  validates :pre_post_id, uniqueness: true, allow_nil: true
  validates :service, inclusion: { in: Shipping::SERVICES.keys.map(&:to_s) }, allow_nil: true
  validates :shipping_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :receiver_obs, length: { maximum: RECEIVER_OBS_LIMIT }, allow_blank: true

  normalizes :receiver_obs, with: ->(value) { value.strip.presence }

  scope :awaiting_tracking, -> {
    where.not(tracking_state: FINAL_TRACKING_STATES)
         .where.not(tracking_code: nil)
         .where("correios_status IS NULL OR correios_status NOT IN (?)", TERMINAL_PREPOST_STATUSES)
  }

  def address
    {
      recipient: receiver_name, cpf: receiver_cpf,
      street: street, number: number, complement: complement,
      neighborhood: neighborhood, city: city, state: state, zip: zip
    }
  end

  def service_label
    Shipping.service_label(service)
  end

  def tracking_url
    "#{TRACKING_URL}?objeto=#{tracking_code}"
  end

  def short_address
    [ [ street, number ].compact_blank.join(", "), [ city, state ].compact_blank.join("/") ]
      .compact_blank
      .join(" · ")
  end

  def correios_status_name
    CORREIOS_STATUSES[correios_status]
  end

  def mark_tracking_unavailable!(error_message)
    update!(
      tracking_state: :unavailable,
      tracking_error: error_message,
      tracking_errored_at: Time.current
    )
  end
end
