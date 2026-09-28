module Shipping
  class RenewReturnCharge < ReturnChargeAction
    private

    def applicable?(charge)
      charge.expired?
    end

    def perform(shipment, charge)
      ReturnFreightCharge.issue(shipment: shipment, amount_cents: charge.amount_cents)
      deliver_charge
    end
  end
end
