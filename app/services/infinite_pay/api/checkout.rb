require "faraday"

module InfinitePay
  module Api
    class Checkout
      include InfinitePay::Api::Client

      def self.create(payload)
        new(payload).create
      end

      def initialize(payload)
        @payload = payload
      end

      def create
        response = post
        raise_for_status(response)
        parse(response.body)["url"] or
          raise InfinitePay::Api::Error, "infinitepay response missing url: #{response.body}"
      end

      private

      attr_reader :payload

      def post
        connection.post("links") do |req|
          req.headers["Accept"]       = "application/json"
          req.headers["Content-Type"] = "application/json"
          req.body = payload.to_json
        end
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
        raise InfinitePay::Api::TransientError, "infinitepay links request failed: #{error.message}"
      end

      def parse(raw)
        JSON.parse(raw.presence || "{}")
      rescue JSON::ParserError => error
        raise InfinitePay::Api::Error, "unparseable infinitepay body: #{error.message}"
      end
    end
  end
end
