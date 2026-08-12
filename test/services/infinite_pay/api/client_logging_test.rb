require "test_helper"

module InfinitePay
  module Api
    class ClientLoggingTest < ActiveSupport::TestCase
      URL = "#{InfinitePay::Api::BASE_URL}/links".freeze
      WEBHOOK_URL = "https://prismagames.com.br/pagamentos/webhook/tok3n".freeze

      PAYLOAD = {
        handle: "prisma_games",
        order_nsu: "PG-04821",
        items: [ { description: "Cartucho Zelda", quantity: 1, price: 18_000 } ],
        customer: { name: "Cliente Confirmado", email: "cliente@example.com" },
        webhook_url: WEBHOOK_URL
      }.freeze

      setup do
        @sink = StringIO.new
        @previous_logger = Rails.logger
        Rails.logger = ActiveSupport::Logger.new(@sink)

        stub_request(:post, URL).to_return(
          status: 200,
          body: { "url" => "https://checkout.infinitepay.io/prisma_games?lenc=abc" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      teardown do
        Rails.logger = @previous_logger
      end

      test "traces the request line, the request body and the response status and body" do
        InfinitePay::Api::Checkout.create(PAYLOAD)

        log = @sink.string
        assert_match %r{request: POST #{Regexp.escape(URL)}}, log
        assert_match "PG-04821", log
        assert_match "Cartucho Zelda", log
        assert_match "response: Status 200", log
        assert_match "lenc=abc", log
      end

      test "logs the webhook url in full so the exact payload we sent is recoverable" do
        InfinitePay::Api::Checkout.create(PAYLOAD)

        assert_match WEBHOOK_URL, @sink.string
      end

      test "traces the response body of a rejected link" do
        stub_request(:post, URL).to_return(status: 422, body: { "message" => "invalid item price" }.to_json)

        assert_raises(InfinitePay::Api::Error) { InfinitePay::Api::Checkout.create(PAYLOAD) }

        log = @sink.string
        assert_match "response: Status 422", log
        assert_match "invalid item price", log
      end
    end
  end
end
