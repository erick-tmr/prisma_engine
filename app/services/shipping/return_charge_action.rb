module Shipping
  class ReturnChargeAction
    Result = Data.define(:error) do
      def success?
        error.nil?
      end
    end

    def self.call(order:)
      new(order: order).call
    end

    def initialize(order:)
      @order = order
    end

    def call
      return failure(:not_awaiting) unless order.awaiting_return?

      shipment = order.return_shipment
      charge = shipment&.freight_charge
      return failure(:no_charge) unless charge && applicable?(charge)

      perform(shipment, charge)
      Result.new(error: nil)
    end

    private

    attr_reader :order

    def deliver_charge
      OrderMailer.awaiting_return(order).deliver_later
    end

    def failure(reason)
      Result.new(error: reason)
    end
  end
end
