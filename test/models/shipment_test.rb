require "test_helper"

class ShipmentTest < ActiveSupport::TestCase
  test "maps a known Correios status to its name" do
    assert_equal :pendente, Shipment.new(correios_status: 7).correios_status_name
    assert_equal :postado, Shipment.new(correios_status: 3).correios_status_name
  end

  test "returns nil for an unknown or absent status" do
    assert_nil Shipment.new(correios_status: 8).correios_status_name
    assert_nil Shipment.new(correios_status: nil).correios_status_name
  end

  test "requires a tracking code" do
    shipment = Shipment.new(tracking_code: nil)

    assert_not shipment.valid?
    assert_includes shipment.errors[:tracking_code], "não pode ficar em branco"
  end

  test "requires a unique tracking code" do
    Shipment.create!(tracking_code: "AA1")
    dup = Shipment.new(tracking_code: "AA1")

    assert_not dup.valid?
    assert_includes dup.errors[:tracking_code], "já está em uso"
  end

  test "requires a unique pre_post_id but allows many without one" do
    Shipment.create!(tracking_code: "AA1", pre_post_id: "PR1")
    dup = Shipment.new(tracking_code: "AA2", pre_post_id: "PR1")
    assert_not dup.valid?

    Shipment.create!(tracking_code: "AA3") # pre_post_id nil
    assert Shipment.new(tracking_code: "AA4").valid? # a second nil pre_post_id is fine
  end

  test "starts in the pending tracking state" do
    assert Shipment.new.tracking_pending?
  end

  test "mark_tracking_unavailable! stops polling and records the error" do
    shipment = Shipment.create!(tracking_code: "A9")

    shipment.mark_tracking_unavailable!("SRO-019: Objeto inválido")

    shipment.reload
    assert shipment.tracking_unavailable?
    assert_equal "SRO-019: Objeto inválido", shipment.tracking_error
    assert_not_nil shipment.tracking_errored_at
    assert_not_includes Shipment.awaiting_tracking, shipment
  end

  test "awaiting_tracking keeps live shipments and drops finished or dead ones" do
    poll_me = Shipment.create!(tracking_code: "A1")
    in_transit = Shipment.create!(tracking_code: "A2", tracking_state: :in_transit)
    Shipment.create!(tracking_code: "A3", tracking_state: :delivered)
    Shipment.create!(tracking_code: "A4", tracking_state: :returned)
    Shipment.create!(tracking_code: "A5", correios_status: 5) # cancelado

    assert_equal [ poll_me.id, in_transit.id ].sort, Shipment.awaiting_tracking.pluck(:id).sort
  end
end
