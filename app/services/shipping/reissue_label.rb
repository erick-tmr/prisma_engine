module Shipping
  class ReissueLabel
    def self.call(shipment)
      new(shipment).call
    end

    def initialize(shipment)
      @shipment = shipment
    end

    def call
      return false unless shipment&.label_expired?

      Shipment.transaction do
        shipment.tracking_events.delete_all
        shipment.reset_for_reissue
        shipment.save!
        shipment.shipping_label&.reset_for_reissue!
      end
      Shipping::EmitLabel.resume(shipment)
      true
    end

    private

    attr_reader :shipment
  end
end
