module Shipping
  class RequestLabelJob < Shipping::LabelStep
    private

    def applicable?(label)
      label.prepost_confirmed?
    end

    def run(shipment, label)
      return unless label.claim_requesting!

      recibo_id = Shipping::RequestLabel.call(shipment)
      label.mark_requested!(recibo_id)
    rescue Correios::Api::Error
      label.unclaim_requesting!
      raise
    end
  end
end
