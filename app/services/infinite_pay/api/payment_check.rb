module InfinitePay
  module Api
    class PaymentCheck
      include InfinitePay::Api::Client

      def self.fetch(order_nsu:, transaction_nsu:, slug:)
        new(order_nsu: order_nsu, transaction_nsu: transaction_nsu, slug: slug).fetch
      end

      def initialize(order_nsu:, transaction_nsu:, slug:)
        @payload = {
          handle:          InfinitePay::Api::HANDLE,
          order_nsu:       order_nsu,
          transaction_nsu: transaction_nsu,
          slug:            slug
        }
      end

      def fetch
        response = post_json("payment_check", payload)
        raise_for_status(response)
        parse(response.body)
      end

      private

      attr_reader :payload
    end
  end
end
