module Shipping
  class EmitLabelsJob < ApplicationJob
    def perform(order_ids)
      Order.where(id: order_ids).find_each do |order|
        Shipping::EmitLabelJob.perform_later(order.id)
      end
    end
  end
end
