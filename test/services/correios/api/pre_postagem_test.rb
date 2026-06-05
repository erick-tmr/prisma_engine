require "test_helper"

module Correios
  module Api
    class PrePostagemTest < ActiveSupport::TestCase
      BASE = Correios::Api::BASE_URL
      URL = "#{BASE}/prepostagem/v1/prepostagens".freeze

      setup do
        @prev_token = ENV["CORREIOS_CARTAO_API_TOKEN"]
        ENV["CORREIOS_CARTAO_API_TOKEN"] = "test-token"
      end

      teardown do
        ENV["CORREIOS_CARTAO_API_TOKEN"] = @prev_token
      end

      test "POSTs the body with the cartão bearer token and returns the parsed response" do
        stub_create(status: 201, body: { "codigoObjeto" => "AD515656026BR" }.to_json)

        response = Correios::Api::PrePostagem.create({ codigoServico: "03220" })

        assert_equal "AD515656026BR", response["codigoObjeto"]
        assert_requested :post, URL, headers: {
          "Authorization" => "Bearer test-token",
          "Content-Type" => "application/json"
        }
      end

      test "treats a 200 as success too" do
        stub_create(status: 200, body: { "codigoObjeto" => "AD1" }.to_json)

        assert_equal "AD1", Correios::Api::PrePostagem.create({})["codigoObjeto"]
      end

      test "raises TransientError on a 503" do
        stub_create(status: 503, body: "unavailable")

        assert_raises(Correios::Api::TransientError) { Correios::Api::PrePostagem.create({}) }
      end

      test "raises a non-transient Error on a 400" do
        stub_create(status: 400, body: "bad request")

        error = assert_raises(Correios::Api::Error) { Correios::Api::PrePostagem.create({}) }
        refute_kind_of Correios::Api::TransientError, error
      end

      test "raises TransientError on a timeout" do
        stub_request(:post, URL).to_timeout

        assert_raises(Correios::Api::TransientError) { Correios::Api::PrePostagem.create({}) }
      end

      private

      def stub_create(status:, body:)
        stub_request(:post, URL)
          .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
      end
    end
  end
end
