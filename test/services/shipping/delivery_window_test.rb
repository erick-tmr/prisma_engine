require "test_helper"

module Shipping
  class DeliveryWindowTest < ActiveSupport::TestCase
    test "opens two business days before the quoted prazo and closes on it" do
      shipment = build_shipment(business_days: 5, posted_at: Time.zone.parse("2026-07-22 10:00:00"))

      window = Shipping::DeliveryWindow.for(shipment)

      assert_equal Date.new(2026, 7, 27), window.first
      assert_equal Date.new(2026, 7, 29), window.last
    end

    test "skips weekends when counting business days" do
      shipment = build_shipment(business_days: 1, posted_at: Time.zone.parse("2026-07-24 18:00:00"))

      window = Shipping::DeliveryWindow.for(shipment)

      assert_equal Date.new(2026, 7, 27), window.first
      assert_equal Date.new(2026, 7, 27), window.last
    end

    test "anchors on today when the parcel has not been posted yet" do
      shipment = build_shipment(business_days: 3, posted_at: nil)

      travel_to Time.zone.parse("2026-07-22 09:00:00") do
        window = Shipping::DeliveryWindow.for(shipment)

        assert_equal Date.new(2026, 7, 23), window.first
        assert_equal Date.new(2026, 7, 27), window.last
      end
    end

    test "returns nothing for a shipment quoted before we stored the prazo" do
      assert_nil Shipping::DeliveryWindow.for(build_shipment(business_days: nil, posted_at: nil))
    end

    private

    def build_shipment(business_days:, posted_at:)
      shipments(:shipped_order).tap do |shipment|
        shipment.delivery_business_days = business_days
        shipment.posted_at = posted_at
      end
    end
  end
end
