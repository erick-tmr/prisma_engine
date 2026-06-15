require "test_helper"

class SyncPendingShipmentsJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "fans out a sync job only for shipments awaiting tracking" do
    poll_me = Shipment.create!(tracking_code: "P1", order: orders(:awaiting))
    in_transit = Shipment.create!(tracking_code: "P2", tracking_state: :in_transit, order: orders(:awaiting))
    Shipment.create!(tracking_code: "D1", tracking_state: :delivered, order: orders(:awaiting))   # final
    Shipment.create!(tracking_code: "C1", correios_status: 5, order: orders(:awaiting))           # cancelado

    assert_enqueued_jobs 2, only: SyncShipmentJob do
      SyncPendingShipmentsJob.perform_now
    end

    assert_enqueued_with(job: SyncShipmentJob, args: [ poll_me.id ])
    assert_enqueued_with(job: SyncShipmentJob, args: [ in_transit.id ])
  end

  test "enqueues nothing when no shipment needs tracking" do
    Shipment.create!(tracking_code: "D1", tracking_state: :delivered, order: orders(:awaiting))

    assert_no_enqueued_jobs do
      SyncPendingShipmentsJob.perform_now
    end
  end
end
