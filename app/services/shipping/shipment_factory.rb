module Shipping
  # Builds (or updates) a Shipment from a Correios pré-postagem payload — the
  # response returned when a pré-postagem is created. Idempotent on tracking_code,
  # so re-running with a refreshed payload updates the same shipment.
  #
  #   Shipping::ShipmentFactory.from_pre_postagem(payload) # payload: Hash or JSON String
  class ShipmentFactory
    def self.from_pre_postagem(payload)
      new(payload).build
    end

    def initialize(payload)
      parsed = payload.is_a?(String) ? JSON.parse(payload) : payload
      @payload = parsed.deep_stringify_keys
    end

    def build
      shipment = Shipment.find_or_initialize_by(tracking_code: payload.fetch("codigoObjeto"))
      shipment.assign_attributes(attributes)
      warn_unknown_status(shipment)
      shipment.save!
      shipment
    end

    private

    attr_reader :payload

    def attributes
      {
        pre_post_id: payload["id"],
        service_code: payload["codigoServico"],
        service: Shipping::SERVICES.key(payload["codigoServico"]),
        weight_grams: payload["pesoInformado"],
        width_cm: payload["larguraInformada"],
        height_cm: payload["alturaInformada"],
        length_cm: payload["comprimentoInformado"],
        correios_status: payload["statusAtual"],
        correios_status_label: payload["descStatusAtual"],
        correios_status_at: Correios::Api::Timestamp.parse(payload["dataHoraStatusAtual"]),
        posting_deadline: Correios::Api::Timestamp.parse(payload["prazoPostagem"]),
        requested_at: Correios::Api::Timestamp.parse(payload["dataHora"]),
        pre_post_payload: payload
      }
    end

    # descStatusAtual + the raw payload are always kept, but an unmapped status code
    # (e.g. a future 8) means our map is stale — log loudly so we notice and extend it.
    def warn_unknown_status(shipment)
      status = shipment.correios_status
      return if status.nil? || Shipment::CORREIOS_STATUSES.key?(status)

      Rails.logger.error(
        "[correios-prepost] unknown status=#{status} " \
        "desc=#{shipment.correios_status_label.inspect} " \
        "tracking_code=#{shipment.tracking_code}"
      )
    end
  end
end
