module Payments
  class PaymentUpdate
    def self.call(order:, payload:)
      new(order: order, payload: payload).call
    end

    def initialize(order:, payload:)
      @order   = order
      @payload = payload
    end

    def call
      return log_skip("order_nsu mismatch") unless reconciled?
      return log_skip("paid_amount mismatch") unless amount_matches?

      order.with_lock { confirm! if confirmable? }
    end

    private

    attr_reader :order, :payload

    def reconciled?
      payload["order_nsu"].to_s == order.number
    end

    def amount_matches?
      payload["paid_amount"].to_i == order.total_cents
    end

    def confirmable?
      order.awaiting_payment? || order.cancelled?
    end

    def confirm!
      order.update!(
        external_id:    payload["transaction_nsu"],
        receipt_url:    payload["receipt_url"],
        payment_method: payload["capture_method"]
      )
      order.confirm_payment!
    end

    def log_skip(reason)
      Rails.logger.warn("Payments::PaymentUpdate skipped order #{order.number}: #{reason}")
      nil
    end
  end
end
