require "test_helper"

module Correios
  module Api
    class RotuloRequestTest < ActiveSupport::TestCase
      BASE = Correios::Api::BASE_URL
      URL = "#{BASE}/prepostagem/v1/prepostagens/rotulo/assincrono/pdf".freeze

      setup do
        @prev_token = ENV["CORREIOS_CARTAO_API_TOKEN"]
        ENV["CORREIOS_CARTAO_API_TOKEN"] = "test-token"
      end

      teardown do
        ENV["CORREIOS_CARTAO_API_TOKEN"] = @prev_token
      end

      test "POSTs the body with the cartão bearer token and returns the parsed response" do
        stub_request(:post, URL).to_return(
          status: 201, body: { "idRecibo" => "R1" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

        response = Correios::Api::RotuloRequest.create({ idsPrePostagem: [ "PR1" ] })

        assert_equal "R1", response["idRecibo"]
        assert_requested :post, URL, headers: {
          "Authorization" => "Bearer test-token",
          "Content-Type" => "application/json"
        }
      end

      test "treats a 200 as success too" do
        stub_request(:post, URL).to_return(
          status: 200, body: { "idRecibo" => "R2" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

        assert_equal "R2", Correios::Api::RotuloRequest.create({})["idRecibo"]
      end

      test "raises TransientError on a 503" do
        stub_request(:post, URL).to_return(status: 503, body: "unavailable")

        assert_raises(Correios::Api::TransientError) { Correios::Api::RotuloRequest.create({}) }
      end

      test "raises a non-transient Error on a 400" do
        stub_request(:post, URL).to_return(status: 400, body: "bad request")

        error = assert_raises(Correios::Api::Error) { Correios::Api::RotuloRequest.create({}) }
        refute_kind_of Correios::Api::TransientError, error
      end

      test "raises TransientError on a timeout" do
        stub_request(:post, URL).to_timeout

        assert_raises(Correios::Api::TransientError) { Correios::Api::RotuloRequest.create({}) }
      end
    end
  end
end
