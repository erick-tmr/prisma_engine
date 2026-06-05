require "faraday"

module Correios
  module Api
    # Shared HTTP plumbing for the Correios::Api clients (Tracking, PrePostagem):
    # one Faraday connection to Correios::Api::BASE_URL, the same timeouts, and a
    # single status check that maps 429/5xx onto the retryable TransientError.
    module Client
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 15

      private

      def connection
        Faraday.new(url: Correios::Api::BASE_URL) do |conn|
          conn.options.open_timeout = OPEN_TIMEOUT
          conn.options.timeout = READ_TIMEOUT
          conn.adapter Faraday.default_adapter
        end
      end

      def raise_for_status(response, ok: [ 200 ])
        status = response.status
        return if ok.include?(status)
        raise Correios::Api::TransientError, "correios returned #{status}" if status == 429 || status >= 500

        raise Correios::Api::Error, "correios returned #{status}: #{response.body}"
      end
    end
  end
end
