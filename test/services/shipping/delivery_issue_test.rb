require "test_helper"

module Shipping
  class DeliveryIssueTest < ActiveSupport::TestCase
    test "reads the kind and the Correios instruction off the failed-delivery event" do
      shipment = shipments(:labeled)
      add_event(shipment, 0, "OEC", "01", "Objeto saiu para entrega ao destinatário")
      add_event(shipment, 1, "BDE", "98", "Objeto não entregue - Endereço insuficiente",
                "Por favor, aguarde. Será informada aqui a unidade em que o objeto ficará disponível para retirada")

      issue = Shipping::DeliveryIssue.for(shipment)

      assert_equal :awaiting_pickup, issue.kind
      assert_equal :correios, issue.contact
      assert_equal "Por favor, aguarde. Será informada aqui a unidade em que o objeto ficará disponível para retirada",
                   issue.detail
    end

    test "reads the latest issue when the object failed delivery more than once" do
      shipment = shipments(:labeled)
      add_event(shipment, 0, "BDE", "98", "Objeto não entregue - Endereço insuficiente", "Primeira tentativa")
      add_event(shipment, 1, "RO", "01", "Objeto em transferência - por favor aguarde")
      add_event(shipment, 2, "BDE", "98", "Objeto não entregue - Endereço insuficiente", "Segunda tentativa")

      assert_equal "Segunda tentativa", Shipping::DeliveryIssue.for(shipment).detail
    end

    test "falls back to the unknown kind when no event explains the issue" do
      shipment = shipments(:labeled)
      add_event(shipment, 0, "RO", "01", "Objeto em transferência - por favor aguarde")

      issue = Shipping::DeliveryIssue.for(shipment)

      assert_equal Shipping::DeliveryIssue::UNKNOWN, issue.kind
      assert_equal :support, issue.contact
      assert_nil issue.detail
    end

    private

    def add_event(shipment, position, code, type, description, detalhe = nil)
      shipment.tracking_events.create!(
        position: position, event_code: code, event_type: type, description: description,
        occurred_at: Time.current, payload: { "detalhe" => detalhe }.compact
      )
    end
  end
end
