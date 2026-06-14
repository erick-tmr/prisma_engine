module Payments
  class WebhooksController < ActionController::API
    def create
      order = Order.find_by(webhook_token: params[:token])
      unless order
        Rails.logger.warn("Payments webhook rejected: unrecognized token")
        return head :unauthorized
      end

      ActiveRecord::Base.transaction do
        order.payment_webhook_events.create!(headers: captured_headers, payload: payload)
        Payments::PaymentUpdate.call(order: order, payload: payload)
      end
      head :ok
    end

    private

    def payload
      @payload ||= JSON.parse(request.raw_post)
    end

    def captured_headers
      request.headers.env.select { |key, _| key.start_with?("HTTP_", "CONTENT_") }
    end
  end
end
