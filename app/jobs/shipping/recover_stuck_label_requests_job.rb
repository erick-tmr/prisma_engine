module Shipping
  class RecoverStuckLabelRequestsJob < ApplicationJob
    STALE_AFTER = 10.minutes

    def perform
      ShippingLabel.requesting.where(requesting_at: ..STALE_AFTER.ago).find_each do |label|
        Shipping::EmitLabel.recover(label.shipment.order)
      end
    end
  end
end
