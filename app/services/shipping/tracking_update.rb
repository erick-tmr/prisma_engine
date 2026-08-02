module Shipping
  class TrackingUpdate
    EVENT_SIGNALS = {
      %w[FC 82] => :label_issued,
      %w[PO 01] => :in_transit,
      %w[RO 01] => :in_transit,
      %w[DO 01] => :in_transit,
      %w[OEC 01] => :in_transit,
      %w[BDE 01] => :delivered,
      %w[BDE 20] => :in_transit
    }.freeze

    UNIQUE_BY = %i[shipment_id position].freeze
    UPDATE_ONLY = %i[tracking_code event_code event_type description occurred_at payload].freeze

    def self.apply(shipment, events)
      new(shipment, events).apply
    end

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
        record_events
        update_shipment
        discard_label if posted?
      end
    end

    private

    attr_reader :shipment, :events

    def record_events
      log_unmapped_events
      stamped_at = Time.current
      rows = events.each_with_index.map do |event, position|
        {
          shipment_id: shipment.id, position: position, tracking_code: shipment.tracking_code,
          event_code: event[:code], event_type: event[:type], description: event[:description],
          occurred_at: event[:occurred_at], payload: event[:payload] || {},
          created_at: stamped_at, updated_at: stamped_at
        }
      end
      ShipmentTrackingEvent.upsert_all(rows, unique_by: UNIQUE_BY, update_only: UPDATE_ONLY)
    end

    def log_unmapped_events
      known = shipment.tracking_events.where(position: 0...events.size).pluck(:position).to_set
      events.each_with_index do |event, position|
        next if known.include?(position) || EVENT_SIGNALS.key?(key(event))

        Rails.logger.warn(
          "[correios-rastro] unmapped event code=#{event[:code]} type=#{event[:type]} " \
          "desc=#{event[:description].inspect} tracking_code=#{shipment.tracking_code}"
        )
      end
    end

    def update_shipment
      latest = events.last
      shipment.tracking_state = derive_state
      shipment.last_tracking_status = latest[:description] || latest[:code]
      shipment.last_tracked_at = latest[:occurred_at] || Time.current
      shipment.posted_at ||= first_movement_at
      shipment.delivered_at = delivered_at if shipment.tracking_delivered?
      shipment.save!
    end

    def first_movement_at
      events.find { |event| moved?(event) }&.dig(:occurred_at)
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

    def moved?(event)
      signal(event) != :label_issued
    end

    def posted?
      events.any? { |event| key(event) == ShipmentTrackingEvent::POSTED }
    end

    def discard_label
      shipment.shipping_label&.destroy
    end

    def delivered_at
      events.reverse.find { |event| signal(event) == :delivered }[:occurred_at]
    end
  end
end
