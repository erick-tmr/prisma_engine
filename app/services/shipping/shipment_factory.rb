module Shipping
  class ShipmentFactory
    def self.update_from_pre_postagem(shipment, payload)
      new(shipment, payload).update
    end

    def initialize(shipment, payload)
      @shipment = shipment
      parsed = payload.is_a?(String) ? JSON.parse(payload) : payload
      @payload = parsed.deep_stringify_keys
    end

    def update
      pinned = Shipment.where(id: shipment.id, pre_post_id: nil).update_all(attributes)
      shipment.reload
      pinned.zero? ? log_discarded_duplicate : warn_unknown_status
      shipment
    end

    private

    attr_reader :shipment, :payload

    def log_discarded_duplicate
      Rails.logger.info(
        "[correios-prepost] discarded duplicate pré-postagem id=#{payload["id"].inspect} " \
        "for shipment=#{shipment.id}; kept pre_post_id=#{shipment.pre_post_id.inspect}"
      )
    end

    def attributes
      reader = Correios::Api::Payload
      {
        tracking_code: reader.string(payload, "codigoObjeto").presence,
        pre_post_id: reader.string(payload, "id").presence,
        service_code: reader.string(payload, "codigoServico").presence,
        correios_status: reader.integer(payload, "statusAtual"),
        correios_status_label: reader.string(payload, "descStatusAtual").presence,
        correios_status_at: reader.time(payload, "dataHoraStatusAtual"),
        posting_deadline: reader.time(payload, "prazoPostagem"),
        requested_at: reader.time(payload, "dataHora"),
        pre_post_payload: payload
      }
    end

    def warn_unknown_status
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
