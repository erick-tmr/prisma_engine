module Shipping
  class DownloadLabel
    Result = Data.define(:filename, :pdf_base64)

    def self.call(recibo_id)
      response = Correios::Api::RotuloDownload.fetch(recibo_id)
      context = "rótulo download (recibo #{recibo_id})"
      Result.new(
        filename: Correios::Api::Payload.require_string(response, "nome", context),
        pdf_base64: Correios::Api::Payload.require_string(response, "dados", context)
      )
    end
  end
end
