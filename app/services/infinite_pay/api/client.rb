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
          conn.adapter Faraday.default_adapter
        end
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
