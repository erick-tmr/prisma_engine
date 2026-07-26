require "faraday"

module Meta
  module Api
    module Client
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 15
      REDACT_BEARER = [ /(Bearer )[^"\s]+/, '\1[REDACTED]' ].freeze
      REDACT_TOKEN = [ /(access_token=)[^"&\s]+/, '\1[REDACTED]' ].freeze
      TRANSIENT_ERROR_CODES = [ 1, 2, 4, 17, 32, 341, 613, 80_014 ].freeze

      private

      def connection
        Faraday.new(url: Meta::Api::BASE_URL) do |conn|
          conn.options.open_timeout = OPEN_TIMEOUT
          conn.options.timeout = READ_TIMEOUT
          trace_requests(conn)
          conn.adapter Faraday.default_adapter
        end
      end

      def trace_requests(conn)
        conn.response :logger, Rails.logger, { headers: true, bodies: true, log_level: :info } do |logger|
          logger.filter(*REDACT_BEARER)
          logger.filter(*REDACT_TOKEN)
        end
      end

      def raise_for_status(response, ok: [ 200 ])
        status = response.status
        return if ok.include?(status)
        raise Meta::Api::TransientError, "meta returned #{status}: #{response.body}" if transient?(status, response.body)

        raise Meta::Api::PermanentError, "meta returned #{status}: #{response.body}"
      end

      def transient?(status, body)
        return true if status == 429 || status >= 500

        TRANSIENT_ERROR_CODES.include?(meta_error_code(body))
      end

      def meta_error_code(body)
        JSON.parse(body.presence || "{}").dig("error", "code")
      rescue JSON::ParserError
        nil
      end
    end
  end
end
