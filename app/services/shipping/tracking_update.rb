module Shipping
  class TrackingUpdate
    EVENT_SIGNALS = {
      %w[FC 82]  => :label_issued,
      %w[FC 83]  => :label_expired,
      %w[FC 07]  => :attempt_failed,
      %w[PO 01]  => :posted,
      %w[PO 09]  => :posted,
      %w[RO 01]  => :in_transit,
      %w[DO 01]  => :in_transit,
      %w[OEC 01] => :in_transit,
      %w[BDE 01] => :delivered,
      %w[BDE 20] => :in_transit,
      %w[BDE 98] => :awaiting_pickup,
      %w[BDI 01] => :delivered,
      %w[LDI 01] => :held_for_pickup
    }.freeze

    MOVEMENT_SIGNALS = %i[posted in_transit delivered awaiting_pickup].freeze

    UNIQUE_BY = %i[shipment_id position].freeze
    UPDATE_ONLY = %i[tracking_code event_code event_type description occurred_at payload].freeze

    def self.apply(shipment, events)
      new(shipment, events).apply
    end

    def self.signal_for(code, type)
      EVENT_SIGNALS[[ code, type ]]
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
        next if known.include?(position) || signal(event)

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
      expire_dead_prepost
      shipment.save!
    end

    def expire_dead_prepost
      return unless any_signal?(:label_expired) && events.none? { |event| moved?(event) }

      expiry = events.reverse.find { |event| signal(event) == :label_expired }
      shipment.expire_prepost(label: expiry[:description], at: expiry[:occurred_at])
    end

    def first_movement_at
      events.find { |event| moved?(event) }&.dig(:occurred_at)
    end

    def derive_state
      return "returned" if any_signal?(:returned)
      return "delivered" if any_signal?(:delivered)

      issue = issue_state
      return issue if issue
      return "in_transit" if events.any? { |event| moved?(event) }

      "pending"
    end

    def issue_state
      latest = events.reverse.find { |event| DeliveryIssue.issue?(signal(event)) }

      latest && DeliveryIssue.state_for(signal(latest))
    end

    def any_signal?(kind)
      events.any? { |event| signal(event) == kind }
    end

    def signal(event)
      self.class.signal_for(event[:code], event[:type])
    end

    def moved?(event)
      MOVEMENT_SIGNALS.include?(signal(event))
    end

    def posted?
      any_signal?(:posted)
    end

    def discard_label
      shipment.shipping_label&.destroy
    end

    def delivered_at
      events.reverse.find { |event| signal(event) == :delivered }[:occurred_at]
    end
  end
end
