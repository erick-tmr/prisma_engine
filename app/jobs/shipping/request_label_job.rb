module Shipping
  class RequestLabelJob < Shipping::LabelStep
    private

    def applicable?(label)
      label.prepost_created?
    end

    def run(order, label)
      recibo_id = Shipping::RequestLabel.call(order.shipment)
      label.mark_requested!(recibo_id)
    end
  end
end
