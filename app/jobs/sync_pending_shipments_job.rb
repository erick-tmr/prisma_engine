class SyncPendingShipmentsJob < ApplicationJob
  def perform
    Shipment.awaiting_tracking.find_each do |shipment|
      SyncShipmentJob.perform_later(shipment.id)
    end
  end
end
