module Shipping
  class DownloadLabelJob < Shipping::LabelStep
    private

    def applicable?(label)
      label.requested?
    end

    def run(_shipment, label)
      result = Shipping::DownloadLabel.call(label.recibo_id)
      label.store_label!(filename: result.filename, pdf: result.pdf_base64)
    end
  end
end
