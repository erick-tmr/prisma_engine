class SyncPendingShipmentsJob < ApplicationJob
  # Hourly orchestrator (scheduled in config/recurring.yml). Fans out one sync job
  # per shipment that still needs tracking, so each syncs in isolation with its own
  # retries and rate limiting — one slow or failing object can't block the rest.
  def perform
    Shipment.awaiting_tracking.find_each do |shipment|
      SyncShipmentJob.perform_later(shipment.id)
    end
  end
end
