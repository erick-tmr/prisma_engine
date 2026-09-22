module Admin
  class ShipmentTrack
    STATE_CLASSES = {
      "pending"        => "pending",
      "in_transit"     => "transit",
      "delivered"      => "done",
      "returned"       => "bounced",
      "delivery_issue" => "issue",
      "unavailable"    => "issue"
    }.freeze

    Entry = Data.define(:shipment, :events) do
      delegate :tracking_code, :tracking_url, :service_label, :created_at, :superseded_at, to: :shipment

      def past?
        shipment.superseded?
      end

      def state
        shipment.tracking_state
      end

      def state_class
        STATE_CLASSES.fetch(state)
      end
    end

    def self.for(order, direction)
      live = direction == "inbound" ? order.return_shipment : order.shipment
      past = order.past_shipments.select { |shipment| shipment.direction == direction }
      shipments = past + [ live ].compact.select { |shipment| past.any? || trackable?(shipment) }
      new(direction, shipments) if shipments.any?
    end

    def self.trackable?(shipment)
      shipment.tracking_code.present? || shipment.tracking_events.any?
    end
    private_class_method :trackable?

    attr_reader :direction, :entries

    def initialize(direction, shipments)
      @direction = direction
      @entries = shipments.map do |shipment|
        Entry.new(shipment: shipment, events: shipment.tracking_events.sort_by(&:occurred_at).reverse)
      end
    end

    def navigable?
      entries.size > 1
    end

    def latest_index
      entries.size - 1
    end
  end
end
