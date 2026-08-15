module Shipping
  class CancelReturn
    SOURCES = Order::TRANSITIONS.select { |_, targets| targets.include?("delivered") }
                                .keys.intersection(Shipping::RETURN_WALK).freeze

    Result = Data.define(:error) do
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
      return failure(:not_cancellable) unless SOURCES.include?(order.status)

      shipment = order.return_shipment
      return failure(:no_return) unless shipment
      return failure(:already_posted) if shipment.posted_at

      withdraw(shipment)
    end

    private

    attr_reader :order, :actor

    def withdraw(shipment)
      Order.transaction do
        shipment.destroy!
        order.update!(return_reason: nil)
        order.transition_to!("delivered", actor: actor)
      end
      Result.new(error: nil)
    end

    def failure(reason)
      Result.new(error: reason)
    end
  end
end
