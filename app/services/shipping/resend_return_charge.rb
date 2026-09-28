module Shipping
  class ResendReturnCharge < ReturnChargeAction
    private

    def applicable?(charge)
      charge.pending?
    end

    def perform(_shipment, _charge)
      deliver_charge
    end
  end
end
