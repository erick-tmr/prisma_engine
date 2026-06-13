module Payments
  # nosemgrep: ruby.lang.security.missing-csrf-protection.missing-csrf-protection
  class WebhooksController < ActionController::Base
    skip_forgery_protection

    def create
      # TODO(reopen): capture-only for now. Once the real payload shape is confirmed,
      # process it here (Payments::PaymentUpdate) — a paid webhook should confirm an
      # awaiting_payment order AND reopen + confirm one we auto-cancelled after the 24h
      # timeout (Order: cancelled → payment_confirmed), since the InfinitePay link may
      # outlive our window. Until then we only persist the raw payload below.
      Payments::WebhookCapture.record(
        headers: request.headers.env.select { |key, _| key.start_with?("HTTP_", "CONTENT_") },
        body:    request.raw_post
      )
      head :ok
    end
  end
end
