module Shipping
  class Reship
    CLONED = (StartReturn::CLONED + %i[shipping_cents receiver_obs]).freeze

    Result = Data.define(:shipment, :error) do
      def success?
        error.nil?
      end
    end

    def self.call(order:, service: nil)
      new(order, service: service).call
    end

    def self.reshippable?(order)
      return false unless order.returned?

      shipment = order.shipment
      returned_at = order.status_changes.where(to_status: "returned").maximum(:created_at)
      !!(shipment && returned_at && shipment.created_at < returned_at)
    end

    def initialize(order, service: nil)
      @order = order
      @service = service.presence || Shipping::DEFAULT_RETURN_SERVICE
    end

    def call
      return failure(:invalid_service) unless Shipping::SERVICES.key?(service.to_sym)

      shipment = Order.transaction do
        order.lock!
        despatch if self.class.reshippable?(order)
      end
      return failure(:not_reshippable) unless shipment

      Shipping::EmitLabel.resume(shipment)
      Result.new(shipment: shipment, error: nil)
    end

    private

    attr_reader :order, :service

    def despatch
      snapshot = snapshot_of(order.shipment)
      now = Time.current
      Shipment.current.where(order: order).update_all(superseded_at: now, updated_at: now)
      order.reload
      Shipment.create!(order: order, direction: :outbound, **snapshot)
    end

    def snapshot_of(previous)
      same_service = previous.service == service
      previous.slice(*CLONED).symbolize_keys.merge(
        service: service,
        delivery_business_days: (previous.delivery_business_days if same_service)
      )
    end

    def failure(reason)
      Result.new(shipment: nil, error: reason)
    end
  end
end
