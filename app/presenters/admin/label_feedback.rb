module Admin
  class LabelFeedback
    RUNNING_STATES = %w[prepost_created prepost_confirmed requesting requested label_downloaded].freeze
    IN_FLIGHT = %w[queued running].freeze
    ERROR_LIMIT = 120

    def initialize(order)
      @order = order
      @shipment = order.tracked_shipment
      @label = @shipment&.shipping_label
    end

    attr_reader :order, :shipment, :label

    delegate :number, to: :order

    def state
      return "expired" if expired?
      return "done" if done?
      return "failed" if failed?
      return "queued" if label&.pending?
      return "running" if running?

      "idle"
    end

    def in_flight?
      IN_FLIGHT.include?(state)
    end

    def settled?
      done? || failed? || expired?
    end

    def expired?
      shipment&.label_expired? || false
    end

    def done?
      return false unless label&.ready?

      order.return_leg? || order.label_issued?
    end

    def failed?
      label&.errored_at.present?
    end

    def running?
      RUNNING_STATES.include?(label&.state)
    end

    def step
      label&.state
    end

    def code
      order.shipment&.tracking_code
    end

    def error_message
      label&.error.to_s.truncate(ERROR_LIMIT)
    end

    def since
      label&.updated_at
    end
  end
end
