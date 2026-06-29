require "test_helper"

module Correios
  module Api
    class PrazoTest < ActiveSupport::TestCase
      URL = "#{Correios::Api::BASE_URL}/prazo/v1/nacional".freeze

      test "POSTs a batched request with one parametrosPrazo per service code" do
        stub_request(:post, URL).to_return(
          status:  200,
          body:    [
            { "coProduto" => "03220", "nuRequisicao" => "03220", "prazoEntrega" => 2 },
            { "coProduto" => "03298", "nuRequisicao" => "03298", "prazoEntrega" => 7 }
          ].to_json,
          headers: { "Content-Type" => "application/json" }
        )

        rows = Correios::Api.stub(:api_token, "test-api") do
          Correios::Api::Prazo.fetch(
            cep_origem: "37600000", cep_destino: "01310100",
            service_codes: [ "03220", "03298" ]
          )
        end

        assert_equal 2, rows.length
        assert_equal 7, rows.last["prazoEntrega"]

        assert_requested(:post, URL) do |req|
          body = JSON.parse(req.body)
          assert_equal "Bearer test-api", req.headers["Authorization"]
          assert_equal 2, body["parametrosPrazo"].length
          first = body["parametrosPrazo"].first
          assert_equal "03220", first["coProduto"]
          assert_equal "03220", first["nuRequisicao"]
          assert_equal "37600000", first["cepOrigem"]
          assert_equal "01310100", first["cepDestino"]
          true
        end
      end

      test "raises InvalidObjectError on a 422" do
        stub_request(:post, URL).to_return(status: 422, body: "{}")
        assert_raises(Correios::Api::InvalidObjectError) do
          Correios::Api::Prazo.fetch(cep_origem: "37600000", cep_destino: "00000000",
                                     service_codes: [ "03220" ])
        end
      end

      test "raises TransientError on 5xx and timeouts" do
        stub_request(:post, URL).to_return(status: 500, body: "boom")
        assert_raises(Correios::Api::TransientError) do
          Correios::Api::Prazo.fetch(cep_origem: "37600000", cep_destino: "01310100",
                                     service_codes: [ "03220" ])
        end

        stub_request(:post, URL).to_timeout
        assert_raises(Correios::Api::TransientError) do
          Correios::Api::Prazo.fetch(cep_origem: "37600000", cep_destino: "01310100",
                                     service_codes: [ "03220" ])
        end
      end

      test "raises Error when the body is not JSON" do
        stub_request(:post, URL).to_return(status: 200, body: "<html>oops</html>")
        error = assert_raises(Correios::Api::Error) do
          Correios::Api::Prazo.fetch(cep_origem: "37600000", cep_destino: "01310100",
                                     service_codes: [ "03220" ])
        end
        refute_kind_of Correios::Api::TransientError,     error
        refute_kind_of Correios::Api::InvalidObjectError, error
      end
    end
  end
end
