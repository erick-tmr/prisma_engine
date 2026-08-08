module Shipping
  module DeliveryIssue
    UNKNOWN = :unknown

    ISSUES = {
      awaiting_pickup: { state: "delivery_issue", contact: :correios }
    }.freeze

    Issue = Data.define(:kind, :event) do
      def detail
        event&.detail
      end

      def contact
        ISSUES.dig(kind, :contact) || :support
      end
    end

    def self.issue?(signal)
      ISSUES.key?(signal)
    end

    def self.state_for(signal)
      ISSUES.dig(signal, :state)
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
