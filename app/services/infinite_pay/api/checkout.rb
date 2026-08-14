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
        response = post_json("links", payload)
        raise_for_status(response)
        parse(response.body)["url"] or
          raise InfinitePay::Api::Error, "infinitepay response missing url: #{response.body}"
      end

      private

      attr_reader :payload
    end
  end
end
