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

    # An item with no statusAtual is Correios still assembling the object, not a
    # move backwards: writing the nil through would erase a status we already
    # confirmed, so it stays pending and the job reschedules itself.
    def refresh_status(item)
      reader = Correios::Api::Payload
      status = reader.integer(item, "statusAtual")
      raise Shipping::PrePostagemPending, "#{shipment.tracking_code} has no statusAtual yet" if status.nil?

      shipment.update!(
        correios_status: status,
        correios_status_label: reader.string(item, "descStatusAtual").presence,
        correios_status_at: reader.time(item, "dataHoraStatusAtual")
      )
    end
  end
end
