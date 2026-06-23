require "faraday"

module Correios
  module Api
    # Shared HTTP plumbing for the Correios::Api clients (Tracking, PrePostagem,
    # CEP, …): one Faraday connection to Correios::Api::BASE_URL, the same
    # timeouts, a single status check that maps 429/5xx onto the retryable
    # TransientError, and a full request/response trace to log/correios-poll.log
    # with the Bearer credential redacted so it never reaches disk.
    module Client
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 15
      LOG_PATH = Rails.root.join("log", "correios-poll.log")
      REDACT_BEARER = [ /(Bearer )[^"\s]+/, '\1[REDACTED]' ].freeze

      def self.request_logger
        @request_logger ||= ActiveSupport::Logger.new(LOG_PATH)
      end

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
        conn.response :logger, Correios::Api::Client.request_logger, { headers: true, bodies: true } do |logger|
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
