module Shipping
  class DownloadDce
    Result = Data.define(:filename, :pdf_base64)

    def self.call(shipment)
      new(shipment).call
    end

    def initialize(shipment)
      @shipment = shipment
    end

    def call
      body = Correios::Api::DaceDownload.fetch(shipment.pre_post_id)
      verify_objeto!(body)
      Result.new(
        filename: "declaracao-#{shipment.order.number}.pdf",
        pdf_base64: Correios::Api::Payload.require_string(body, "dados", context)
      )
    end

    private

    attr_reader :shipment

    def context
      "DACE (pré-postagem #{shipment.pre_post_id})"
    end

    # The response echoes back the ids it answered for. Storing a document we
    # cannot tie to this shipment would put someone else's declaração in the
    # customer's download, so a mismatch is fatal rather than logged.
    def verify_objeto!(body)
      objetos = Array(Correios::Api::Payload.hash(body)["objetos"])
      return if objetos.include?(shipment.pre_post_id)

      raise Correios::Api::InvalidObjectError,
            "#{context}: came back for #{objetos.inspect}"
    end
  end
end
