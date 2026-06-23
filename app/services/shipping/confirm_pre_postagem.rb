module Shipping
  class ConfirmPrePostagem
    PREPOSTADO = 2

    def self.call(shipment)
      new(shipment).call
    end

    def initialize(shipment)
      @shipment = shipment
    end

    def call
      raise Shipping::PrePostagemPending, "no tracking code yet" if shipment.tracking_code.blank?

      item = Correios::Api::PrePostagemStatus.fetch(shipment.tracking_code)
      raise Shipping::PrePostagemPending, "#{shipment.tracking_code} not visible yet" if item.blank?

      refresh_status(item)
      return shipment if shipment.correios_status == PREPOSTADO

      raise Shipping::PrePostagemPending,
            "#{shipment.tracking_code} is #{shipment.correios_status_label} (#{shipment.correios_status})"
    end

    private

    attr_reader :shipment

    def refresh_status(item)
      shipment.update!(
        correios_status: item["statusAtual"],
        correios_status_label: item["descStatusAtual"],
        correios_status_at: Correios::Api::Timestamp.parse(item["dataHoraStatusAtual"])
      )
    end
  end
end
