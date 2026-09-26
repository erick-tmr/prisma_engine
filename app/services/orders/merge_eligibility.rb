module Orders
  class MergeEligibility
    STATUSES = {
      checkout:   Order::CHECKOUT_MERGEABLE_STATUSES,
      backoffice: Order::MERGEABLE_STATUSES
    }.freeze

    Verdict = Data.define(:reason) do
      def ok?
        reason.nil?
      end
    end

    def self.for(order, origin:)
      new(order, origin).verdict
    end

    def initialize(order, origin)
      @order = order
      @origin = origin
      @shipment = order.shipment
    end

    def verdict
      Verdict.new(reason: blocking_reason)
    end

    private

    attr_reader :order, :origin, :shipment

    def blocking_reason
      return :status unless STATUSES.fetch(origin).include?(order.status)
      return :no_shipment unless shipment
      return :posted if posted?
      return :label_in_flight if label_in_flight?
      return :prepost if checkout? && shipment.tracking_code

      :pending_plan if !checkout? && OrderMerge.awaiting_carrier_payment.involving(order).exists?
    end

    def checkout?
      origin == :checkout
    end

    def posted?
      shipment.posted_at.present? || !shipment.tracking_pending?
    end

    def label_in_flight?
      label = shipment.shipping_label
      return false if label.nil? || label.ready? || label.errored_at.present?

      !shipment.label_expired?
    end
  end
end
