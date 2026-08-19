require "test_helper"

module Shipping
  class TrackingUpdateTest < ActiveSupport::TestCase
    test "uncatalogued_codes lists observed (code,type) pairs not in EVENT_SIGNALS" do
      shipment = Shipment.create!(order: bare_order, tracking_code: "PG999000111BR")
      shipment.tracking_events.create!(position: 0, event_code: "PO", event_type: "01",
                                       description: "Objeto postado")
      shipment.tracking_events.create!(position: 1, event_code: "ZZ", event_type: "99",
                                       description: "Evento misterioso")

      result = Shipping::TrackingUpdate.uncatalogued_codes
      pairs = result.map { |row| [ row[:code], row[:type] ] }

      assert_includes pairs, %w[ZZ 99]
      assert_not_includes pairs, %w[PO 01]
      mystery = result.find { |row| row[:code] == "ZZ" }
      assert_equal "Evento misterioso", mystery[:description]
    end

    test "discards the label once the object is posted" do
      shipment = shipments(:labeled)
      assert shipment.shipping_label.present?

      Shipping::TrackingUpdate.apply(shipment, [ label_event, posted_event ])

      assert_nil shipment.reload.shipping_label
    end

    test "posting without a label is a no-op" do
      shipment = shipments(:awaiting)
      assert_nil shipment.shipping_label

      assert_nothing_raised { Shipping::TrackingUpdate.apply(shipment, [ posted_event ]) }
      assert_nil shipment.reload.shipping_label
    end

    test "keeps the label while only the label-issued event is present" do
      shipment = shipments(:labeled)

      Shipping::TrackingUpdate.apply(shipment, [ label_event ])

      assert shipment.reload.shipping_label.present?
    end

    test "stamps posted_at from the first movement and never moves it again" do
      shipment = shipments(:labeled)

      Shipping::TrackingUpdate.apply(shipment, [ label_event, posted_event ])
      assert_equal posted_event[:occurred_at], shipment.reload.posted_at

      Shipping::TrackingUpdate.apply(shipment, [ label_event, posted_event, delivered_event ])
      assert_equal posted_event[:occurred_at], shipment.reload.posted_at
    end

    test "leaves posted_at empty while the object has not moved" do
      shipment = shipments(:labeled)

      Shipping::TrackingUpdate.apply(shipment, [ label_event ])

      assert_nil shipment.reload.posted_at
    end

    test "replaying the same feed neither raises nor duplicates a position" do
      shipment = shipments(:labeled)

      Shipping::TrackingUpdate.apply(shipment, [ label_event, posted_event ])
      assert_nothing_raised { Shipping::TrackingUpdate.apply(shipment, [ label_event, posted_event ]) }

      positions = shipment.reload.tracking_events.pluck(:position)
      assert_equal [ 0, 1 ], positions.sort
      assert_equal positions.uniq, positions
    end

    test "a row already at that position is refreshed rather than inserted again" do
      shipment = shipments(:labeled)
      Shipping::TrackingUpdate.apply(shipment, [ posted_event ])
      original = shipment.reload.tracking_events.find_by(position: 0)

      Shipping::TrackingUpdate.apply(shipment, [ delivered_event ])

      row = shipment.reload.tracking_events.find_by(position: 0)
      assert_equal original.id, row.id
      assert_equal "BDE", row.event_code
      assert_equal "Objeto entregue ao destinatário", row.description
    end

    test "refreshing a row keeps the moment it was first seen and moves updated_at" do
      shipment = shipments(:labeled)
      Shipping::TrackingUpdate.apply(shipment, [ posted_event ])
      original = shipment.reload.tracking_events.find_by(position: 0)
      original.update_columns(created_at: 2.days.ago, updated_at: 2.days.ago)
      first_seen = original.reload.created_at

      Shipping::TrackingUpdate.apply(shipment, [ delivered_event ])

      row = shipment.reload.tracking_events.find_by(position: 0)
      assert_equal first_seen.to_i, row.created_at.to_i
      assert_operator row.updated_at, :>, 1.minute.ago
    end

    test "a row written by a concurrent sync is adopted instead of colliding" do
      shipment = shipments(:labeled)
      shipment.tracking_events.create!(position: 0, event_code: "XX", event_type: "99")

      assert_nothing_raised { Shipping::TrackingUpdate.apply(shipment, [ posted_event ]) }

      assert_equal "PO", shipment.reload.tracking_events.find_by(position: 0).event_code
    end

    test "a failed delivery attempt puts the shipment in delivery_issue" do
      shipment = shipments(:labeled)

      Shipping::TrackingUpdate.apply(shipment, [ label_event, posted_event, failed_delivery_event ])

      assert shipment.reload.tracking_delivery_issue?
      assert_equal "Objeto não entregue - Endereço insuficiente", shipment.last_tracking_status
    end

    test "delivery_issue survives later movement, since the object still needs attention" do
      shipment = shipments(:labeled)
      transfer = event("RO", "01", "Objeto em transferência - por favor aguarde", Time.utc(2026, 5, 27, 9, 0, 0))

      Shipping::TrackingUpdate.apply(shipment, [ posted_event, failed_delivery_event, transfer ])

      assert shipment.reload.tracking_delivery_issue?
    end

    test "a delivery after a failed attempt clears the issue" do
      shipment = shipments(:labeled)

      Shipping::TrackingUpdate.apply(shipment, [ posted_event, failed_delivery_event, delivered_event ])

      assert shipment.reload.tracking_delivered?
    end

    test "an expired label is not movement, so the order is left where it is" do
      shipment = shipments(:labeled)

      Shipping::TrackingUpdate.apply(shipment, [ label_event, expired_event ])

      shipment.reload
      assert shipment.tracking_pending?
      assert_nil shipment.posted_at
    end

    test "an expired label marks the pre-postagem terminal so polling stops" do
      shipment = shipments(:labeled)

      Shipping::TrackingUpdate.apply(shipment, [ label_event, expired_event ])

      shipment.reload
      assert shipment.label_expired?
      assert_equal "Etiqueta expirada", shipment.correios_status_label
      assert_equal expired_event[:occurred_at], shipment.correios_status_at
      assert_not_includes Shipment.awaiting_tracking, shipment
    end

    test "an expiry alongside real movement leaves the pre-postagem alone" do
      shipment = shipments(:labeled)

      Shipping::TrackingUpdate.apply(shipment, [ label_event, expired_event, posted_event ])

      shipment.reload
      assert_not shipment.label_expired?
      assert shipment.tracking_in_transit?
    end

    test "an uncatalogued code is not read as movement" do
      shipment = shipments(:labeled)
      mystery = event("ZZ", "99", "Evento misterioso", Time.utc(2026, 5, 22, 15, 0, 0))

      Shipping::TrackingUpdate.apply(shipment, [ label_event, mystery ])

      shipment.reload
      assert shipment.tracking_pending?
      assert_nil shipment.posted_at
    end

    test "a late posting counts as posting and discards the label" do
      shipment = shipments(:labeled)

      Shipping::TrackingUpdate.apply(shipment, [ label_event, late_posted_event ])

      shipment.reload
      assert_nil shipment.shipping_label
      assert shipment.tracking_in_transit?
      assert_equal late_posted_event[:occurred_at], shipment.posted_at
    end

    test "a delivery reported as BDI still marks the shipment delivered" do
      shipment = shipments(:labeled)
      handover = event("BDI", "01", "Objeto entregue ao destinatário", Time.utc(2026, 5, 26, 11, 3, 0))

      Shipping::TrackingUpdate.apply(shipment, [ posted_event, failed_delivery_event, handover ])

      shipment.reload
      assert shipment.tracking_delivered?
      assert_equal handover[:occurred_at], shipment.delivered_at
    end

    test "codes catalogued as carrying no signal neither move nor flag the shipment" do
      shipment = shipments(:labeled)
      held = event("LDI", "01", "Objeto aguardando retirada no endereço indicado", Time.utc(2026, 5, 26, 12, 0, 0))
      attempt = event("FC", "07", "Objeto não entregue - carteiro não atendido", Time.utc(2026, 5, 26, 13, 0, 0))

      Shipping::TrackingUpdate.apply(shipment, [ label_event, held, attempt ])

      shipment.reload
      assert shipment.tracking_pending?
      assert_nil shipment.posted_at
    end

    test "codes catalogued as carrying no signal stop being reported as unmapped" do
      shipment = shipments(:labeled)
      held = event("LDI", "01", "Objeto aguardando retirada no endereço indicado", Time.utc(2026, 5, 26, 12, 0, 0))
      logged = 0

      Rails.logger.stub(:warn, ->(_message) { logged += 1 }) do
        Shipping::TrackingUpdate.apply(shipment, [ held ])
      end

      assert_equal 0, logged
    end

    test "an unmapped code is logged only the first time that position is seen" do
      shipment = shipments(:labeled)
      mystery = event("ZZ", "99", "Evento misterioso", Time.utc(2026, 5, 22, 15, 0, 0))
      logged = 0
      logger = ->(_message) { logged += 1 }

      Rails.logger.stub(:warn, logger) do
        Shipping::TrackingUpdate.apply(shipment, [ mystery ])
        Shipping::TrackingUpdate.apply(shipment, [ mystery ])
      end

      assert_equal 1, logged
    end

    private

    def posted_event
      event("PO", "01", "Objeto postado", Time.utc(2026, 5, 22, 14, 51, 2))
    end

    def label_event
      event("FC", "82", "Etiqueta emitida", Time.utc(2026, 5, 22, 13, 11, 4))
    end

    def delivered_event
      event("BDE", "01", "Objeto entregue ao destinatário", Time.utc(2026, 5, 26, 11, 3, 0))
    end

    def failed_delivery_event
      event("BDE", "98", "Objeto não entregue - Endereço insuficiente", Time.utc(2026, 5, 26, 18, 47, 30))
    end

    def expired_event
      event("FC", "83", "Etiqueta expirada", Time.utc(2026, 6, 5, 3, 11, 39))
    end

    def late_posted_event
      event("PO", "09", "Objeto postado após o horário limite da unidade", Time.utc(2026, 5, 22, 20, 4, 0))
    end

    def event(code, type, description, occurred_at)
      { code: code, type: type, description: description, occurred_at: occurred_at, payload: {} }
    end
  end
end
