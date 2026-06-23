require "test_helper"

class ShipmentTrackingEventTest < ActiveSupport::TestCase
  test "requires a shipment" do
    event = ShipmentTrackingEvent.new(position: 0)

    assert_not event.valid?
    assert_includes event.errors[:shipment], "é obrigatório(a)"
  end

  test "links to a shipment" do
    shipment = Shipment.create!(tracking_code: "AA1", order: orders(:awaiting))
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
end
