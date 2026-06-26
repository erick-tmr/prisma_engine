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
  end
end
