module Shipping
  class AssumeReturnFreight < ReturnChargeAction
    private

    def applicable?(charge)
      !charge.paid?
    end

    def perform(shipment, _charge)
      Order.transaction do
        shipment.return_freight_charges.live.update_all(voided_at: Time.current)
        Shipping::EmitLabel.resume(shipment)
      end
    end
  end
end
