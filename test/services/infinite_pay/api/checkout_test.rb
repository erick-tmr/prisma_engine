require "test_helper"

module InfinitePay
  module Api
    class CheckoutTest < ActiveSupport::TestCase
      URL = "#{InfinitePay::Api::BASE_URL}/links".freeze

      PAYLOAD = {
        handle: "prisma_games",
        order_nsu: "PG-202606130001",
        items: [ { description: "Cartucho", quantity: 1, price: 18_000 } ]
      }.freeze

      test "POSTs the payload to /links and returns the checkout url" do
        stub_request(:post, URL).to_return(
          status: 200,
          body: { "url" => "https://checkout.infinitepay.io/prisma_games?lenc=abc" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

        url = InfinitePay::Api::Checkout.create(PAYLOAD)

        assert_equal "https://checkout.infinitepay.io/prisma_games?lenc=abc", url
        assert_requested(:post, URL) do |req|
          body = JSON.parse(req.body)
          assert_equal "prisma_games", body["handle"]
          assert_equal "PG-202606130001", body["order_nsu"]
          assert_equal 18_000, body["items"].first["price"]
          assert_equal "application/json", req.headers["Content-Type"]
          true
        end
      end

      test "raises Error when a 200 response carries no url" do
        stub_request(:post, URL).to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })
        assert_raises(InfinitePay::Api::Error) { InfinitePay::Api::Checkout.create(PAYLOAD) }
      end

      test "raises Error on an unparseable body" do
        stub_request(:post, URL).to_return(status: 200, body: "not json")
        assert_raises(InfinitePay::Api::Error) { InfinitePay::Api::Checkout.create(PAYLOAD) }
      end

      test "raises Error on a 4xx" do
        stub_request(:post, URL).to_return(status: 422, body: "bad request")
        assert_raises(InfinitePay::Api::Error) { InfinitePay::Api::Checkout.create(PAYLOAD) }
      end

      test "raises TransientError on a 429" do
        stub_request(:post, URL).to_return(status: 429, body: "slow down")
        assert_raises(InfinitePay::Api::TransientError) { InfinitePay::Api::Checkout.create(PAYLOAD) }
      end

      test "raises TransientError on a 5xx" do
        stub_request(:post, URL).to_return(status: 503, body: "down")
        assert_raises(InfinitePay::Api::TransientError) { InfinitePay::Api::Checkout.create(PAYLOAD) }
      end

      test "raises TransientError on a timeout" do
        stub_request(:post, URL).to_timeout
        assert_raises(InfinitePay::Api::TransientError) { InfinitePay::Api::Checkout.create(PAYLOAD) }
      end
    end
  end
end
