module Shipping
  class DownloadDceJob < Shipping::LabelStep
    private

    def applicable?(label)
      label.label_downloaded?
    end

    def run(shipment, label)
      result = Shipping::DownloadDce.call(shipment)
      Order.transaction do
        label.store_dce!(filename: result.filename, pdf: result.pdf_base64)
        Shipping::Leg.for(shipment).announce_label(shipment.order)
      end
    end
  end
end
