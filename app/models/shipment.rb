class Shipment < ApplicationRecord
  # Correios pré-postagem status (statusAtual). The label (descStatusAtual) and the
  # full raw payload are persisted too, so an unmapped code still carries its meaning.
  CORREIOS_STATUSES = {
    1 => :preatendido,
    2 => :prepostado,
    3 => :postado,
    4 => :expirado,
    5 => :cancelado,
    6 => :estornado,
    7 => :pendente
  }.freeze

  # Tracking lifecycle derived from rastro events (see SyncShipmentJob). Distinct
  # from correios_status (pré-postagem), which only describes the label/posting.
  enum :tracking_state,
       { pending: 0, in_transit: 1, delivered: 2, returned: 3, unavailable: 4 },
       prefix: :tracking

  # Reaching one of these stops the polling loop (and will later trigger the order
  # to its final state — see docs/architecture.md).
  FINAL_TRACKING_STATES = %w[delivered returned unavailable].freeze

  # Pré-postagem codes that never become a real shipment: expirado, cancelado,
  # estornado. No point polling rastro for them.
  TERMINAL_PREPOST_STATUSES = [ 4, 5, 6 ].freeze

  has_many :tracking_events,
           class_name: "ShipmentTrackingEvent",
           dependent: :destroy

  validates :tracking_code, presence: true, uniqueness: true
  validates :pre_post_id, uniqueness: true, allow_nil: true

  # Shipments still worth polling: have a tracking code, aren't in a final
  # tracking state, and aren't a dead pré-postagem. A NULL correios_status (no
  # pré-postagem status yet) still counts as pollable, so it's kept explicitly —
  # `NOT IN (...)` alone would drop NULLs.
  scope :awaiting_tracking, -> {
    where.not(tracking_state: FINAL_TRACKING_STATES)
         .where.not(tracking_code: nil)
         .where("correios_status IS NULL OR correios_status NOT IN (?)", TERMINAL_PREPOST_STATUSES)
  }

  def correios_status_name
    CORREIOS_STATUSES[correios_status]
  end

  # A rastro response rejected the code as permanently invalid (SRO-019): stop
  # polling and record the error so a bad code in our DB is debuggable (it
  # shouldn't happen — codes come from Correios' own pré-postagem).
  def mark_tracking_unavailable!(error_message)
    update!(
      tracking_state: :unavailable,
      tracking_error: error_message,
      tracking_errored_at: Time.current
    )
  end
end
