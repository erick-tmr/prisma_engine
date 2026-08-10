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

  test "a planned shipment without a tracking code is valid" do
    assert Shipment.new(order: orders(:awaiting)).valid?
  end

  test "only accepts a service we offer" do
    assert Shipment.new(order: orders(:awaiting), service: "sedex").valid?
    assert_not Shipment.new(order: orders(:awaiting), service: "carrier_pigeon").valid?
  end

  test "rejects a negative shipping price" do
    assert_not Shipment.new(order: orders(:awaiting), shipping_cents: -1).valid?
  end

  test "rejects a receiver_obs longer than the limit" do
    within = Shipment.new(order: orders(:awaiting), receiver_obs: "a" * Shipment::RECEIVER_OBS_LIMIT)
    over = Shipment.new(order: orders(:awaiting), receiver_obs: "a" * (Shipment::RECEIVER_OBS_LIMIT + 1))

    assert within.valid?
    assert_not over.valid?
  end

  test "normalizes a blank receiver_obs to nil" do
    shipment = Shipment.create!(order: orders(:awaiting), receiver_obs: "  entregar na portaria  ")
    assert_equal "entregar na portaria", shipment.receiver_obs

    shipment.update!(receiver_obs: "   ")
    assert_nil shipment.receiver_obs
  end

  test "address exposes the snapshot as a symbol-keyed hash" do
    assert_equal(
      {
        recipient: "Cliente Confirmado", cpf: "52998224725",
        street: "Rua das Flores", number: "150", complement: "Apto 12",
        neighborhood: "Centro", city: "São Paulo", state: "SP", zip: "01310100"
      },
      shipments(:awaiting).address
    )
  end

  test "short_address condenses the snapshot to one line" do
    assert_equal "Rua das Flores, 150 · São Paulo/SP", shipments(:awaiting).short_address
    assert_equal "", Shipment.new.short_address
  end

  test "service_label spells the Correios product out" do
    assert_equal "PAC", shipments(:awaiting).service_label
    assert_equal "SEDEX", shipments(:shipped_order).service_label
    assert_equal "", Shipment.new.service_label
  end

  test "tracking_url points the customer at the Correios lookup for this parcel" do
    assert_equal(
      "https://rastreamento.correios.com.br/app/index.php?objetos=PG515656026BR",
      shipments(:delivered).tracking_url
    )
  end

  test "requires a unique tracking code" do
    Shipment.create!(tracking_code: "AA1", order: orders(:awaiting))
    dup = Shipment.new(tracking_code: "AA1", order: orders(:awaiting))

    assert_not dup.valid?
    assert_includes dup.errors[:tracking_code], "já está em uso"
  end

  test "requires a unique pre_post_id but allows many without one" do
    Shipment.create!(tracking_code: "AA1", pre_post_id: "PR1", order: orders(:awaiting))
    dup = Shipment.new(tracking_code: "AA2", pre_post_id: "PR1", order: orders(:awaiting))
    assert_not dup.valid?

    Shipment.create!(tracking_code: "AA3", order: orders(:awaiting)) # pre_post_id nil
    assert Shipment.new(tracking_code: "AA4", order: orders(:awaiting)).valid? # a second nil pre_post_id is fine
  end

  test "starts in the pending tracking state" do
    assert Shipment.new.tracking_pending?
  end

  test "mark_tracking_unavailable! stops polling and records the error" do
    shipment = Shipment.create!(tracking_code: "A9", order: orders(:awaiting))

    shipment.mark_tracking_unavailable!("SRO-019: Objeto inválido")

    shipment.reload
    assert shipment.tracking_unavailable?
    assert_equal "SRO-019: Objeto inválido", shipment.tracking_error
    assert_not_nil shipment.tracking_errored_at
    assert_not_includes Shipment.awaiting_tracking, shipment
  end

  test "awaiting_tracking keeps live shipments and drops finished or dead ones" do
    poll_me = Shipment.create!(tracking_code: "A1", order: orders(:awaiting))
    in_transit = Shipment.create!(tracking_code: "A2", tracking_state: :in_transit, order: orders(:awaiting))
    Shipment.create!(tracking_code: "A3", tracking_state: :delivered, order: orders(:awaiting))
    Shipment.create!(tracking_code: "A4", tracking_state: :returned, order: orders(:awaiting))
    Shipment.create!(tracking_code: "A5", correios_status: 5, order: orders(:awaiting)) # cancelado

    assert_equal [ poll_me.id, in_transit.id ].sort, Shipment.awaiting_tracking.pluck(:id).sort
  end
end
