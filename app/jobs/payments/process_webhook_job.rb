module Payments
  class ProcessWebhookJob < ApplicationJob
    retry_on ActiveRecord::Deadlocked,
             ActiveRecord::LockWaitTimeout,
             wait: :polynomially_longer, attempts: 5

    def perform(event_id)
      event = PaymentWebhookEvent.find_by(id: event_id)
      return unless event

      Payments::PaymentUpdate.call(order: event.order, payload: event.payload)
    end
  end
end
