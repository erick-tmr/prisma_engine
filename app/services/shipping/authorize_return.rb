module Shipping
  class AuthorizeReturn
    SOURCES = Order::TRANSITIONS.select { |_, targets| targets.include?("awaiting_return") }.keys.freeze

    CLONED = %i[
      service weight_grams height_cm width_cm length_cm
      receiver_name receiver_cpf zip street number complement neighborhood city state
    ].freeze

    Result = Data.define(:return_shipment, :error) do
      def success?
        error.nil?
      end
    end

    def self.call(order:, actor: nil)
      new(order: order, actor: actor).call
    end

    def initialize(order:, actor: nil)
      @order = order
      @actor = actor
    end

    def call
      return failure(:not_returnable) unless SOURCES.include?(order.status)
      return failure(:no_shipment) unless order.shipment
      return failure(:already_open) if order.return_shipment

      authorize
    rescue ActiveRecord::RecordNotUnique
      failure(:already_open)
    end

    private

    attr_reader :order, :actor

    def authorize
      shipment = nil
      Order.transaction do
        shipment = Shipment.create!(order: order, direction: :inbound, **snapshot)
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
