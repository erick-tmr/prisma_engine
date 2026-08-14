require "test_helper"

module InfinitePay
  module Api
    class PaymentCheckTest < ActiveSupport::TestCase
      URL = "#{InfinitePay::Api::BASE_URL}/payment_check".freeze

      PAID = {
        "success" => true, "paid" => true, "amount" => 19_984,
        "paid_amount" => 21_500, "installments" => 3, "capture_method" => "credit_card"
      }.freeze

      def fetch
        InfinitePay::Api::PaymentCheck.fetch(order_nsu: "PG-12345", transaction_nsu: "tx-abc", slug: "uXnT2kndIV")
      end

      test "POSTs the identifiers to /payment_check and returns the parsed status" do
        stub_request(:post, URL).to_return(
          status: 200, body: PAID.to_json, headers: { "Content-Type" => "application/json" }
        )

        assert_equal PAID, fetch
        assert_requested(:post, URL) do |req|
          body = JSON.parse(req.body)
          assert_equal "prisma_games", body["handle"]
          assert_equal "PG-12345", body["order_nsu"]
          assert_equal "tx-abc", body["transaction_nsu"]
          assert_equal "uXnT2kndIV", body["slug"]
          assert_equal "application/json", req.headers["Content-Type"]
          true
        end
      end

      test "treats an empty 200 body as an empty status" do
        stub_request(:post, URL).to_return(status: 200, body: "")
        assert_empty fetch
      end

      test "raises Error on an unparseable body" do
        stub_request(:post, URL).to_return(status: 200, body: "not json")
        assert_raises(InfinitePay::Api::Error) { fetch }
      end

      test "raises Error on a 4xx" do
        stub_request(:post, URL).to_return(status: 404, body: "unknown transaction")
        assert_raises(InfinitePay::Api::Error) { fetch }
      end

      test "raises TransientError on a 429" do
        stub_request(:post, URL).to_return(status: 429, body: "slow down")
        assert_raises(InfinitePay::Api::TransientError) { fetch }
      end

      test "raises TransientError on a 5xx" do
        stub_request(:post, URL).to_return(status: 502, body: "down")
        assert_raises(InfinitePay::Api::TransientError) { fetch }
      end

      test "raises TransientError on a timeout" do
        stub_request(:post, URL).to_timeout
        assert_raises(InfinitePay::Api::TransientError) { fetch }
      end
    end
  end
end
