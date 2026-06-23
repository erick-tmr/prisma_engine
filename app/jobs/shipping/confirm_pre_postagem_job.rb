module Shipping
  class ConfirmPrePostagemJob < ApplicationJob
    retry_on Correios::Api::TransientError,
             ActiveRecord::Deadlocked,
             ActiveRecord::LockWaitTimeout,
             wait: :polynomially_longer, attempts: 5

    limits_concurrency to: 5, key: "correios_cartao"

    def perform(order_id, attempt = 1)
      @order = Order.find_by(id: order_id)
      return unless @order

      @shipment = @order.shipment
      @label = @shipment&.shipping_label
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
      Shipping::EmitLabel.resume(@order)
    end

    def reschedule_or_fail(attempt, error)
      if attempt < Shipping::PREPOSTAGEM_MAX_POLL_ATTEMPTS
        self.class.set(wait: Shipping::PREPOSTAGEM_POLL_INTERVAL).perform_later(@order.id, attempt + 1)
      else
        @label.record_error!(error.message)
      end
    end
  end
end
