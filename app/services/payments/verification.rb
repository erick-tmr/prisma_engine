module Payments
  class Verification
    Result = Data.define(:payload, :retryable) do
      def verified?
        payload.present?
      end
    end

    REJECTED = Result.new(payload: nil, retryable: false)
    UNPAID   = Result.new(payload: nil, retryable: true)

    def self.call(order:, payload:)
      new(order: order, payload: payload).call
    end

    def initialize(order:, payload:)
      @order   = order
      @payload = payload
    end

    def call
      return reject("order is #{order.status}, not awaiting payment") unless confirmable?
      return reject("delivery carries no transaction_nsu or invoice_slug") if identifiers_missing?
      return reject("order_nsu mismatch") unless reconciled?

      interpret(InfinitePay::Api::PaymentCheck.fetch(order_nsu: order.number, transaction_nsu: transaction_nsu, slug: slug))
    end

    private

    attr_reader :order, :payload

    def confirmable?
      order.awaiting_payment? || order.cancelled?
    end

    def identifiers_missing?
      transaction_nsu.blank? || slug.blank?
    end

    def reconciled?
      payload["order_nsu"].to_s == order.number
    end

    def interpret(check)
      return reject("infinitepay does not recognize the transaction: #{check}") unless check["success"]
      return unpaid("infinitepay reports the transaction as unpaid: #{check}") unless check["paid"]

      Result.new(payload: confirmed_payload(check), retryable: false)
    end

    def confirmed_payload(check)
      {
        "order_nsu"       => order.number,
        "paid_amount"     => check["paid_amount"],
        "capture_method"  => check["capture_method"],
        "transaction_nsu" => transaction_nsu,
        "invoice_slug"    => slug,
        "receipt_url"     => payload["receipt_url"]
      }
    end

    def transaction_nsu
      payload["transaction_nsu"]
    end

    def slug
      payload["invoice_slug"]
    end

    def reject(reason)
      log(reason)
      REJECTED
    end

    def unpaid(reason)
      log(reason)
      UNPAID
    end

    def log(reason)
      Rails.logger.warn("[Payments::Verification] order=#{order.number} #{reason}")
    end
  end
end
