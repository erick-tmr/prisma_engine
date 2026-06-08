require "test_helper"

module Correios
  module Api
    class CepTest < ActiveSupport::TestCase
      BASE = Correios::Api::BASE_URL
      CEP = "37665000".freeze
      URL = "#{BASE}/cep/v2/enderecos/#{CEP}".freeze

      setup do
        @prev_token = ENV["CORREIOS_API_TOKEN"]
        ENV["CORREIOS_API_TOKEN"] = "test-token"
      end

      teardown do
        ENV["CORREIOS_API_TOKEN"] = @prev_token
      end

      test "GETs the CEP endpoint with the bearer token and returns the parsed body" do
        stub_lookup(status: 200, body: town_wide_body)

        body = Correios::Api::Cep.find(CEP)

        assert_requested :get, URL,
          headers: { "Authorization" => "Bearer test-token", "Accept" => "application/json" }
        assert_equal "MG", body["uf"]
        assert_equal "Costas", body["localidade"]
        assert_equal "Paraisópolis", body["localidadeSuperior"]
      end

      test "returns the street-specific shape verbatim" do
        stub_lookup(status: 200, body: street_body)

        body = Correios::Api::Cep.find(CEP)

        assert_equal "Avenida Paulista", body["logradouro"]
        assert_equal "Bela Vista", body["bairro"]
        assert_equal "São Paulo", body["nomeMunicipio"]
      end

      test "raises InvalidObjectError on a 404 (CEP not in Correios' base)" do
        stub_lookup(status: 404, body: { "message" => "CEP nao encontrado" }.to_json)

        assert_raises(Correios::Api::InvalidObjectError) { Correios::Api::Cep.find(CEP) }
      end

      test "raises TransientError on a 429" do
        stub_lookup(status: 429, body: "slow down")

        assert_raises(Correios::Api::TransientError) { Correios::Api::Cep.find(CEP) }
      end

      test "raises TransientError on a 503" do
        stub_lookup(status: 503, body: "unavailable")

        assert_raises(Correios::Api::TransientError) { Correios::Api::Cep.find(CEP) }
      end

      test "raises TransientError on a timeout" do
        stub_request(:get, URL).to_timeout

        assert_raises(Correios::Api::TransientError) { Correios::Api::Cep.find(CEP) }
      end

      test "raises a non-transient Error on a 401" do
        stub_lookup(status: 401, body: "unauthorized")

        error = assert_raises(Correios::Api::Error) { Correios::Api::Cep.find(CEP) }
        refute_kind_of Correios::Api::TransientError, error
        refute_kind_of Correios::Api::InvalidObjectError, error
      end

      test "raises a non-transient Error when the body is not JSON" do
        stub_lookup(status: 200, body: "<html>not json</html>")

        error = assert_raises(Correios::Api::Error) { Correios::Api::Cep.find(CEP) }
        refute_kind_of Correios::Api::TransientError, error
      end

      test "treats an empty 200 body as an empty hash" do
        stub_lookup(status: 200, body: "")

        assert_equal({}, Correios::Api::Cep.find(CEP))
      end

      private

      def stub_lookup(status:, body:)
        stub_request(:get, URL)
          .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
      end

      def town_wide_body
        {
          "cep" => CEP,
          "uf" => "MG",
          "numeroLocalidade" => 30041,
          "localidade" => "Costas",
          "numeroLocalidadeSuperior" => 35361,
          "localidadeSuperior" => "Paraisópolis",
          "tipoCEP" => 1,
          "clique" => "N",
          "inSituacaoLocalidade" => "0"
        }.to_json
      end

      def street_body
        {
          "cep" => "01310100",
          "uf" => "SP",
          "logradouro" => "Avenida Paulista",
          "bairro" => "Bela Vista",
          "nomeMunicipio" => "São Paulo",
          "tipoCEP" => 2
        }.to_json
      end
    end
  end
end
