require "test_helper"

module Admin
  class ShipmentTrackTest < ActiveSupport::TestCase
    setup { @order = orders(:delivered) }

    def despatch(direction, code: nil, superseded_at: nil, **attrs)
      Shipment.create!(order: @order, direction: direction, tracking_code: code, superseded_at: superseded_at,
                       receiver_name: "Cliente Confirmado", zip: "01310100", **attrs)
    end

    test "a single despatch is one entry, with its events newest first" do
      shipment = orders(:shipped_order).shipment
      track = ShipmentTrack.for(orders(:shipped_order), "outbound")

      assert_equal "outbound", track.direction
      assert_not track.navigable?
      assert_equal 0, track.latest_index
      entry = track.entries.sole
      assert_equal shipment, entry.shipment
      assert_equal %w[DO PO], entry.events.map(&:event_code)
      assert_not entry.past?
    end

    test "the entry carries what the summary strip shows" do
      entry = ShipmentTrack.for(@order, "outbound").entries.sole

      assert_equal "PG515656026BR", entry.tracking_code
      assert_includes entry.tracking_url, "PG515656026BR"
      assert_equal @order.shipment.service_label, entry.service_label
      assert_equal "delivered", entry.state
      assert_equal "done", entry.state_class
    end

    test "every tracking state has a pill class" do
      Shipment.tracking_states.each_key do |state|
        @order.shipment.update_columns(tracking_state: state)

        assert ShipmentTrack.for(@order.reload, "outbound").entries.sole.state_class.present?, state
      end
    end

    test "past despatches come first, oldest to newest, and the live one closes the list" do
      first = @order.shipment
      first.update!(superseded_at: 3.days.ago)
      second = despatch(:outbound, code: "PG515656040BR", superseded_at: 1.day.ago, tracking_state: :returned)
      live = despatch(:outbound)

      track = ShipmentTrack.for(@order.reload, "outbound")

      assert track.navigable?
      assert_equal [ first, second, live ], track.entries.map(&:shipment)
      assert_equal [ true, true, false ], track.entries.map(&:past?)
      assert_equal 2, track.latest_index
      assert_equal "bounced", track.entries.second.state_class
    end

    test "a fresh re-ship without a code yet still stands as the latest entry" do
      @order.shipment.update!(superseded_at: 1.hour.ago)
      live = despatch(:outbound)

      track = ShipmentTrack.for(@order.reload, "outbound")

      assert_equal live, track.entries.last.shipment
      assert_empty track.entries.last.events
    end

    test "a lone despatch with no code and no events is not a track" do
      assert_nil ShipmentTrack.for(orders(:producing), "outbound")
    end

    test "a return with no live leg still shows its past ones" do
      inbound = despatch(:inbound, code: "PG515656041BR", superseded_at: 1.day.ago)

      track = ShipmentTrack.for(@order.reload, "inbound")

      assert_equal [ inbound ], track.entries.map(&:shipment)
      assert track.entries.sole.past?
    end

    test "a return label with no movement yet is already a track" do
      despatch(:inbound, code: "PG515656031BR")

      entry = ShipmentTrack.for(@order.reload, "inbound").entries.sole

      assert_equal "PG515656031BR", entry.tracking_code
      assert_empty entry.events
    end

    test "no return leg at all is no track" do
      assert_nil ShipmentTrack.for(@order, "inbound")
    end
  end
end
