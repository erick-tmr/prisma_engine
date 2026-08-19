require "test_helper"

class ShipmentTrackingEventTest < ActiveSupport::TestCase
  test "requires a shipment" do
    event = ShipmentTrackingEvent.new(position: 0)

    assert_not event.valid?
    assert_includes event.errors[:shipment], "é obrigatório(a)"
  end

  test "links to a shipment" do
    shipment = Shipment.create!(tracking_code: "AA1", order: bare_order)
    event = ShipmentTrackingEvent.create!(shipment: shipment, position: 0)

    assert_equal shipment, event.shipment
  end

  test "summary is the Correios description" do
    event = ShipmentTrackingEvent.new(event_code: "PO", event_type: "01", description: "Objeto postado")
    assert_equal "Objeto postado", event.summary
  end

  test "summary falls back to the code when no description was sent" do
    event = ShipmentTrackingEvent.new(event_code: "ZZ", event_type: "99", description: nil)
    assert_equal "ZZ/99", event.summary
  end

  test "detail is the Correios instruction that came with the event" do
    event = ShipmentTrackingEvent.new(payload: { "detalhe" => "Aguardando postagem pelo remetente" })
    assert_equal "Aguardando postagem pelo remetente", event.detail
  end

  test "detail is nil when the event carries no instruction" do
    assert_nil ShipmentTrackingEvent.new(payload: {}).detail
    assert_nil ShipmentTrackingEvent.new(payload: { "detalhe" => "" }).detail
  end

  test "destination reads the unit type, city and UF from the payload" do
    event = ShipmentTrackingEvent.new(payload: {
      "unidadeDestino" => { "tipo" => "Unidade de Tratamento", "endereco" => { "cidade" => "SAO PAULO", "uf" => "SP" } }
    })
    assert_equal "Unidade de Tratamento - SAO PAULO - SP", event.destination
  end

  test "destination is nil when the event carries no destination unit" do
    assert_nil ShipmentTrackingEvent.new(payload: {}).destination
  end

  test "posting_unit is the receiving agency on the posted event" do
    event = ShipmentTrackingEvent.new(event_code: "PO", event_type: "01", payload: {
      "unidade" => { "tipo" => "Agência dos Correios", "endereco" => { "cidade" => "CAMBUI", "uf" => "MG" } }
    })
    assert_equal "Agência dos Correios - CAMBUI - MG", event.posting_unit
  end

  test "posting_unit is nil for events other than Objeto postado" do
    event = ShipmentTrackingEvent.new(event_code: "BDE", event_type: "01", payload: {
      "unidade" => { "tipo" => "Unidade de Distribuição", "endereco" => { "cidade" => "SAO PAULO", "uf" => "SP" } }
    })
    assert_nil event.posting_unit
  end

  test "posting_unit also reads a posting made after the unit's cut-off time" do
    event = ShipmentTrackingEvent.new(event_code: "PO", event_type: "09", payload: {
      "unidade" => { "tipo" => "Agência dos Correios", "endereco" => { "cidade" => "CAMBUI", "uf" => "MG" } }
    })
    assert event.posted?
    assert_equal "Agência dos Correios - CAMBUI - MG", event.posting_unit
  end
end
