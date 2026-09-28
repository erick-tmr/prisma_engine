module Shipping
  class StartReturn
    SOURCES = Order::TRANSITIONS.select { |_, targets| targets.include?("awaiting_return") }.keys.freeze

    CLONED = %i[
      weight_grams height_cm width_cm length_cm
      receiver_name receiver_cpf zip street number complement neighborhood city state
    ].freeze

    PAYERS = %w[store customer].freeze

    Result = Data.define(:return_shipment, :error) do
      def success?
        error.nil?
      end
    end

    def self.call(order:, actor: nil, service: nil, reason: nil, payer: nil)
      new(order: order, actor: actor, service: service, reason: reason, payer: payer).call
    end

    def initialize(order:, actor: nil, service: nil, reason: nil, payer: nil)
      @order = order
      @actor = actor
      @service = service.presence || Shipping::DEFAULT_RETURN_SERVICE
      @reason = reason
      @payer = payer.presence || PAYERS.first
    end

    def call
      refusal = refusal_reason
      return failure(refusal) if refusal

      price_cents = quote
      return failure(:quote_unavailable) if customer_pays? && price_cents.nil?

      authorize(price_cents)
    rescue ActiveRecord::RecordNotUnique
      failure(:already_open)
    end

    private

    attr_reader :order, :actor, :service, :reason, :payer

    def refusal_reason
      return :not_returnable unless SOURCES.include?(order.status)
      return :invalid_service unless Shipping::SERVICES.key?(service.to_sym)
      return :invalid_payer unless PAYERS.include?(payer)
      return :no_shipment unless order.shipment

      :already_open if order.return_shipment
    end

    def customer_pays?
      payer == "customer"
    end

    def quote
      Shipping::ReturnQuote.price_cents(order.shipment, service)
    rescue Correios::Api::Error
      nil
    end

    def authorize(price_cents)
      shipment = nil
      Order.transaction do
        shipment = Shipment.create!(order: order, direction: :inbound, service: service,
                                    shipping_cents: price_cents, **snapshot)
        ReturnFreightCharge.issue(shipment: shipment, amount_cents: price_cents) if customer_pays?
        order.update!(return_reason: reason)
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
