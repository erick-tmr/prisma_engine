module Shipping
  class EmitLabelsJob < ApplicationJob
    def perform(order_ids)
      Order.where(id: order_ids).find_each do |order|
        Shipping::EmitLabel.resume(order)
      end
    end
  end
end
