module Shipping
  # Reconciles a shipment against its full rastro event history: records each event
  # (idempotent per position) and derives the shipment's tracking_state +
  # delivered_at. Owns the Correios event → our-lifecycle interpretation — domain
  # knowledge that has nothing to do with the HTTP call.
  class TrackingUpdate
    # An event is identified by its (code, type) pair — this maps the ones we've
    # confirmed from a real delivered SEDEX flow in prod to the lifecycle signal they
    # carry. Anything not listed is treated as in-transit movement (if it isn't the
    # label) AND logged as unmapped so we can catalogue it — we don't know the
    # `returned` code yet, for example. Extend as new combinations are observed.
    EVENT_SIGNALS = {
      %w[FC 82] => :label_issued,   # etiqueta emitida — exists but hasn't moved
      %w[PO 01] => :in_transit,     # postado
      %w[RO 01] => :in_transit,     # em transferência
      %w[DO 01] => :in_transit,     # em transferência
      %w[OEC 01] => :in_transit,    # saiu para entrega ao destinatário
      %w[BDE 01] => :delivered      # entregue ao destinatário
    }.freeze

    def self.apply(shipment, events)
      new(shipment, events).apply
    end

    # Distinct (code, type, sample description) the rastro has sent that
    # EVENT_SIGNALS doesn't classify yet — the queue for cataloguing new
    # lifecycle codes (e.g. the returned/extraviado family) from real data.
    def self.uncatalogued_codes
      ShipmentTrackingEvent
        .group(:event_code, :event_type)
        .pluck(:event_code, :event_type, "MIN(description)")
        .reject { |code, type, _description| EVENT_SIGNALS.key?([ code, type ]) }
        .map { |code, type, description| { code: code, type: type, description: description } }
    end

    def initialize(shipment, events)
      @shipment = shipment
      @events = events
    end

    def apply
      return if events.empty?

      ApplicationRecord.transaction do
        events.each_with_index { |event, position| record_event(event, position) }
        update_shipment
      end
    end

    private

    attr_reader :shipment, :events

    def record_event(event, position)
      row = shipment.tracking_events.find_or_initialize_by(position: position)
      log_unmapped(event) if row.new_record? && !EVENT_SIGNALS.key?(key(event))
      row.assign_attributes(
        tracking_code: shipment.tracking_code,
        event_code: event[:code],
        event_type: event[:type],
        description: event[:description],
        occurred_at: event[:occurred_at],
        payload: event[:payload]
      )
      row.save!
    end

    # An uncatalogued (code, type) — it's persisted as a tracking event like any
    # other, but log it too so the codes we don't map yet (e.g. returns) surface for
    # later debugging.
    def log_unmapped(event)
      Rails.logger.warn(
        "[correios-rastro] unmapped event code=#{event[:code]} type=#{event[:type]} " \
        "desc=#{event[:description].inspect} tracking_code=#{shipment.tracking_code}"
      )
    end

    def update_shipment
      latest = events.last
      shipment.tracking_state = derive_state
      shipment.last_tracking_status = latest[:description] || latest[:code]
      shipment.last_tracked_at = latest[:occurred_at] || Time.current
      shipment.delivered_at = delivered_at if shipment.tracking_delivered?
      shipment.save!
    end

    def derive_state
      return "delivered" if any_signal?(:delivered)
      return "in_transit" if events.any? { |event| moved?(event) }

      "pending"
    end

    def any_signal?(kind)
      events.any? { |event| signal(event) == kind }
    end

    def signal(event)
      EVENT_SIGNALS[key(event)]
    end

    def key(event)
      [ event[:code], event[:type] ]
    end

    # Any event other than the prepostagem label means the object left the sender.
    def moved?(event)
      signal(event) != :label_issued
    end

    # Only called once the state is delivered, so a delivery event is guaranteed.
    def delivered_at
      events.reverse.find { |event| signal(event) == :delivered }[:occurred_at]
    end
  end
end
