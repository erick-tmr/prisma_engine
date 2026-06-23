class SyncShipmentJob < ApplicationJob
  # Transient API/DB errors self-heal with growing backoff (~3s, 18s, 83s, 258s,
  # 627s). After the attempts are exhausted the job lands in
  # solid_queue_failed_executions and the next hourly run picks the shipment up
  # again — nothing is lost.
  retry_on Correios::Api::TransientError,
           ActiveRecord::Deadlocked,
           ActiveRecord::LockWaitTimeout,
           wait: :polynomially_longer, attempts: 5

  # Cap concurrent rastro calls so a large fan-out can't trip Correios' rate limit.
  # Measured limit is 50 req/s (burst 55) per contract key; 5 in flight (~30 req/s
  # at ~165ms latency) keeps comfortable headroom and avoids the latency cliff that
  # starts past ~10 concurrent.
  limits_concurrency to: 5, key: "correios_rastro"

  # Fetch the full event history for one shipment (infra) and let the domain
  # reconcile it (Shipping::TrackingUpdate). Idempotent per (shipment, position),
  # so a retry or the next hourly run just updates in place.
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
