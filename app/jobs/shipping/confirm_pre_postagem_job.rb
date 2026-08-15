module Shipping
  class ConfirmPrePostagemJob < ApplicationJob
    retry_on Correios::Api::TransientError,
             ActiveRecord::Deadlocked,
             ActiveRecord::LockWaitTimeout,
             wait: :polynomially_longer, attempts: 5

    limits_concurrency to: 5, key: "correios_cartao"

    def perform(shipment_id:, attempt: 1)
      @shipment = Shipment.find_by(id: shipment_id)
      return unless @shipment

      @label = @shipment.shipping_label
      return unless @label&.prepost_created?

      execute(attempt)
    end

    private

    def execute(attempt)
      confirm
    rescue Shipping::PrePostagemPending => error
      reschedule_or_fail(attempt, error)
    rescue Correios::Api::TransientError
      raise
    rescue Correios::Api::Error => error
      @label.record_error!(error.message)
      raise
    end

    def confirm
      Shipping::ConfirmPrePostagem.call(@shipment)
      @label.mark_prepost_confirmed!
      Shipping::EmitLabel.resume(@shipment)
    end

    def reschedule_or_fail(attempt, error)
      if attempt < Shipping::PREPOSTAGEM_MAX_POLL_ATTEMPTS
        self.class.set(wait: poll_delay(attempt)).perform_later(shipment_id: @shipment.id, attempt: attempt + 1)
      else
        @label.record_error!(error.message)
      end
    end

    def poll_delay(attempt)
      [ Shipping::PREPOSTAGEM_POLL_BASE_DELAY * (2**(attempt - 1)), Shipping::PREPOSTAGEM_POLL_MAX_DELAY ].min
    end
  end
end
