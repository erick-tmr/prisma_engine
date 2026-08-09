module Shipping
  module DeliveryIssue
    UNKNOWN = :unknown

    STATES = { awaiting_pickup: "delivery_issue" }.freeze

    Issue = Data.define(:kind, :event) do
      def detail
        event&.detail
      end
    end

    def self.issue?(signal)
      STATES.key?(signal)
    end

    def self.state_for(signal)
      STATES[signal]
    end

    def self.signal_for(event)
      TrackingUpdate.signal_for(event.event_code, event.event_type)
    end

    def self.for(shipment)
      event = shipment.tracking_events.order(:position).reverse_each.find { |row| issue?(signal_for(row)) }

      Issue.new(kind: event ? signal_for(event) : UNKNOWN, event: event)
    end
  end
end
