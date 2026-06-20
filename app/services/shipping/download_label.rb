module Shipping
  class DownloadLabel
    Result = Data.define(:filename, :pdf_base64)

    def self.call(recibo_id)
      response = Correios::Api::RotuloDownload.fetch(recibo_id)
      Result.new(filename: response.fetch("nome"), pdf_base64: response.fetch("dados"))
    end
  end
end
