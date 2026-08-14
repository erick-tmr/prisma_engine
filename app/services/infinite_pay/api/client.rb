require "faraday"

module InfinitePay
  module Api
    module Client
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 15

      private

      def connection
        Faraday.new(url: InfinitePay::Api::BASE_URL) do |conn|
          conn.options.open_timeout = OPEN_TIMEOUT
          conn.options.timeout = READ_TIMEOUT
          trace_requests(conn)
          conn.adapter Faraday.default_adapter
        end
      end

      def trace_requests(conn)
        conn.response :logger, Rails.logger, { headers: true, bodies: true, log_level: :info }
      end

      def post_json(path, payload)
        connection.post(path) do |req|
          req.headers["Accept"]       = "application/json"
          req.headers["Content-Type"] = "application/json"
          req.body = payload.to_json
        end
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
        raise InfinitePay::Api::TransientError, "infinitepay #{path} request failed: #{error.message}"
      end

      def parse(raw)
        JSON.parse(raw.presence || "{}")
      rescue JSON::ParserError => error
        raise InfinitePay::Api::Error, "unparseable infinitepay body: #{error.message}"
      end

      def raise_for_status(response, ok: [ 200, 201 ])
        status = response.status
        return if ok.include?(status)
        raise InfinitePay::Api::TransientError, "infinitepay returned #{status}" if status == 429 || status >= 500

        raise InfinitePay::Api::Error, "infinitepay returned #{status}: #{response.body}"
      end
    end
  end
end
