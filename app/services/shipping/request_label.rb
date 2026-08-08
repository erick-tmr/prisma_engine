module Shipping
  class RequestLabel
    LABEL_TYPE = "P".freeze
    LABEL_FORMAT = "ET".freeze

    def self.call(shipment)
      new(shipment).call
    end

    def initialize(shipment)
      @shipment = shipment
    end

    def call
      response = Correios::Api::RotuloRequest.create(payload)
      Correios::Api::Payload.require_string(
        response, "idRecibo", "rótulo request for pré-postagem #{shipment.pre_post_id.inspect}"
      )
    end

    private

    attr_reader :shipment

    def payload
      {
        idsPrePostagem: [ shipment.pre_post_id ],
        numeroCartaoPostagem: Shipping::POSTAGE_CARD_NUMBER,
        tipoRotulo: LABEL_TYPE,
        formatoRotulo: LABEL_FORMAT
      }
    end
  end
end
