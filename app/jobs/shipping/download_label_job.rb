module Shipping
  class DownloadLabelJob < Shipping::LabelStep
    private

    def applicable?(label)
      label.requested?
    end

    def run(shipment, label)
      result = Shipping::DownloadLabel.call(label.recibo_id)
      Order.transaction do
        label.mark_ready!(filename: result.filename, pdf: result.pdf_base64)
        Shipping::Leg.for(shipment).announce_label(shipment.order)
      end
    end
  end
end
