module Payments
  class ProcessWebhookJob < ApplicationJob
    retry_on InfinitePay::Api::TransientError,
             ActiveRecord::Deadlocked,
             ActiveRecord::LockWaitTimeout,
             wait: :polynomially_longer, attempts: 5

    limits_concurrency to: 5, key: "infinitepay_payment_check"

    def perform(event_id, attempt = 1)
      event = PaymentWebhookEvent.find_by(id: event_id)
      return unless event

      result = Payments::Verification.call(order: event.order, payload: event.payload)
      return Payments::PaymentUpdate.call(order: event.order, payload: result.payload) if result.verified?

      reschedule(event_id, attempt) if result.retryable
    end

    private

    def reschedule(event_id, attempt)
      if attempt < Payments::VERIFY_MAX_ATTEMPTS
        self.class.set(wait: verify_delay(attempt)).perform_later(event_id, attempt + 1)
      else
        Rails.logger.warn("[Payments::ProcessWebhookJob] event=#{event_id} still unverified after #{attempt} attempts")
      end
    end

    def verify_delay(attempt)
      [ Payments::VERIFY_BASE_DELAY * (2**(attempt - 1)), Payments::VERIFY_MAX_DELAY ].min
    end
  end
end
