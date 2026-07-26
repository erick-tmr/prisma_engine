require "faraday"

module Correios
  module Api
    module Client
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 15
      REDACT_BEARER = [ /(Bearer )[^"\s]+/, '\1[REDACTED]' ].freeze

      private

      def connection
        Faraday.new(url: Correios::Api::BASE_URL) do |conn|
          conn.options.open_timeout = OPEN_TIMEOUT
          conn.options.timeout = READ_TIMEOUT
          trace_requests(conn)
          conn.adapter Faraday.default_adapter
        end
      end

      def trace_requests(conn)
        conn.response :logger, Rails.logger, { headers: true, bodies: true, log_level: :info } do |logger|
          logger.filter(*REDACT_BEARER)
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
