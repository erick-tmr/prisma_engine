module Shipping
  class Reship
    CLONED = (StartReturn::CLONED + %i[service shipping_cents delivery_business_days receiver_obs]).freeze

    Result = Data.define(:shipment, :error) do
      def success?
        error.nil?
      end
    end

    def self.call(order:)
      new(order).call
    end

    def self.reshippable?(order)
      return false unless order.returned?

      shipment = order.shipment
      returned_at = order.status_changes.where(to_status: "returned").maximum(:created_at)
      !!(shipment && returned_at && shipment.created_at < returned_at)
    end

    def initialize(order)
      @order = order
    end

    def call
      shipment = Order.transaction do
        order.lock!
        despatch if self.class.reshippable?(order)
      end
      return Result.new(shipment: nil, error: :not_reshippable) unless shipment

      Shipping::EmitLabel.resume(shipment)
      Result.new(shipment: shipment, error: nil)
    end

    private

    attr_reader :order

    def despatch
      snapshot = order.shipment.slice(*CLONED).symbolize_keys
      now = Time.current
      Shipment.current.where(order: order).update_all(superseded_at: now, updated_at: now)
      order.reload
      Shipment.create!(order: order, direction: :outbound, **snapshot)
    end
  end
end
