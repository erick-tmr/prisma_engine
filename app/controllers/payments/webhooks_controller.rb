module Payments
  # nosemgrep: ruby.lang.security.missing-csrf-protection.missing-csrf-protection
  class WebhooksController < ActionController::Base
    skip_forgery_protection

    def create
      Payments::WebhookCapture.record(
        headers: request.headers.env.select { |key, _| key.start_with?("HTTP_", "CONTENT_") },
        body:    request.raw_post
      )

      # SECURITY: InfinitePay sends no signature, so the per-order webhook_token in the URL is
      # the authenticator — only our POST /links for this order ever transmits it. It rides in
      # the path, so it appears in access logs; impact is bounded (it only confirms that one
      # order, to its known total, idempotently). Don't log the token in our own lines.
      order = Order.find_by(webhook_token: params[:token])
      return head :unauthorized unless order

      Payments::PaymentUpdate.call(order: order, payload: JSON.parse(request.raw_post))
      head :ok
    end
  end
end
