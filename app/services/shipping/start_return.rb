module Shipping
  class StartReturn
    SOURCES = Order::TRANSITIONS.select { |_, targets| targets.include?("awaiting_return") }.keys.freeze

    # The box and the customer's end come from the outbound trip. The service does
    # not: a SEDEX delivery does not imply we want to pay for a SEDEX return.
    CLONED = %i[
      weight_grams height_cm width_cm length_cm
      receiver_name receiver_cpf zip street number complement neighborhood city state
    ].freeze

    Result = Data.define(:return_shipment, :error) do
      def success?
        error.nil?
      end
    end

    def self.call(order:, actor: nil, service: nil)
      new(order: order, actor: actor, service: service).call
    end

    def initialize(order:, actor: nil, service: nil)
      @order = order
      @actor = actor
      @service = service.presence || Shipping::DEFAULT_RETURN_SERVICE
    end

    def call
      return failure(:not_returnable) unless SOURCES.include?(order.status)
      return failure(:invalid_service) unless Shipping::SERVICES.key?(service.to_sym)
      return failure(:no_shipment) unless order.shipment
      return failure(:already_open) if order.return_shipment

      authorize
    rescue ActiveRecord::RecordNotUnique
      failure(:already_open)
    end

    private

    attr_reader :order, :actor, :service

    def authorize
      shipment = nil
      Order.transaction do
        shipment = Shipment.create!(order: order, direction: :inbound, service: service, **snapshot)
        order.transition_to!("awaiting_return", actor: actor)
        Shipping::EmitLabel.resume(shipment)
      end
      Result.new(return_shipment: shipment, error: nil)
    end

    def snapshot
      order.shipment.slice(*CLONED).symbolize_keys
    end

    def failure(reason)
      Result.new(return_shipment: nil, error: reason)
    end
  end
end
