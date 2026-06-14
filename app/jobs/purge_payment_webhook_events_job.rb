class PurgePaymentWebhookEventsJob < ApplicationJob
  RETENTION = 90.days

  def perform
    PaymentWebhookEvent.where(created_at: ..RETENTION.ago).delete_all
  end
end
