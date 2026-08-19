module Shipping
  class ReissueLabelsJob < ApplicationJob
    def perform(order_ids)
      Order.where(id: order_ids).find_each do |order|
        Shipping::ReissueLabel.call(order.tracked_shipment)
      end
    end
  end
end
