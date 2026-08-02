class SyncShipmentJob < ApplicationJob
  retry_on Correios::Api::TransientError,
           ActiveRecord::Deadlocked,
           ActiveRecord::LockWaitTimeout,
           wait: :polynomially_longer, attempts: 5

  limits_concurrency to: 1, key: ->(shipment_id) { shipment_id }

  def perform(shipment_id)
    shipment = Shipment.find_by(id: shipment_id)
    return if shipment.nil?

    events = Correios::Api::Tracking.fetch(shipment.tracking_code)
    Shipping::TrackingUpdate.apply(shipment, events)
    Shipping::OrderProgress.apply(shipment)
  rescue Correios::Api::InvalidObjectError => error
    shipment.mark_tracking_unavailable!(error.message)
  end
end
