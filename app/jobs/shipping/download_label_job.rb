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
        shipment.order.advance_to_label_issued!(automatic: true)
      end
    end
  end
end
