module Shipping
  class EmitLabelJob < ApplicationJob
    def perform(order_id)
      order = Order.find_by(id: order_id)
      return if order.nil?

      Shipping::EmitLabel.resume(order)
    end
  end
end
