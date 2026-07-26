require "test_helper"

module Shipping
  class TrackingUpdateTest < ActiveSupport::TestCase
    test "uncatalogued_codes lists observed (code,type) pairs not in EVENT_SIGNALS" do
      shipment = Shipment.create!(order: orders(:awaiting), tracking_code: "PG999000111BR")
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

    def event(code, type, description, occurred_at)
      { code: code, type: type, description: description, occurred_at: occurred_at, payload: {} }
    end
  end
end
