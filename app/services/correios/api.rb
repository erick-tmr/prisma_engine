module Correios
  # Anti-corruption layer for the Correios API. Every Correios::Api::* client talks
  # HTTP to Correios and returns plain data — none of it knows about our domain
  # (Shipment, business rules). The domain (app/services/shipping) depends on these
  # clients, never the reverse. See docs/architecture.md.
  module Api
    BASE_URL = "https://api.correios.com.br".freeze

    def self.api_token
      Rails.application.credentials.dig(:correios, :api_token)
    end

    def self.cartao_api_token
      Rails.application.credentials.dig(:correios, :cartao_api_token)
    end

    # One error hierarchy for every Correios::Api client.
    Error = Class.new(StandardError)
    # Timeouts, 429s and 5xx — the caller retries these with backoff.
    TransientError = Class.new(Error)
    # A 200 whose body rejects the object as invalid (rastro SRO-019) — permanent,
    # so the caller stops rather than retries.
    InvalidObjectError = Class.new(Error)
  end
end
