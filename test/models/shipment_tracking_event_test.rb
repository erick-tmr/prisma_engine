require "test_helper"

class ShipmentTrackingEventTest < ActiveSupport::TestCase
  test "requires a shipment" do
    event = ShipmentTrackingEvent.new(position: 0)

    assert_not event.valid?
    assert_includes event.errors[:shipment], "é obrigatório(a)"
  end

  test "links to a shipment" do
    shipment = Shipment.create!(tracking_code: "AA1")
    event = ShipmentTrackingEvent.create!(shipment: shipment, position: 0)

    assert_equal shipment, event.shipment
  end
end
