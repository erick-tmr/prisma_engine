require "test_helper"

module Correios
  module Api
    class PrecoTest < ActiveSupport::TestCase
      URL = "#{Correios::Api::BASE_URL}/preco/v1/nacional".freeze

      setup do
        @prev_token = ENV["CORREIOS_API_TOKEN"]
        ENV["CORREIOS_API_TOKEN"] = "test-api"
      end

      teardown do
        ENV["CORREIOS_API_TOKEN"] = @prev_token
      end

      test "POSTs a batched request with one parametrosProduto per service code" do
        stub_request(:post, URL).to_return(
          status:  200,
          body:    [
            { "coProduto" => "03220", "nuRequisicao" => "03220", "pcFinal" => "19,84" },
            { "coProduto" => "03298", "nuRequisicao" => "03298", "pcFinal" => "12,30" }
          ].to_json,
          headers: { "Content-Type" => "application/json" }
        )

        rows = Correios::Api::Preco.fetch(
          cep_origem:    "37600000",
          cep_destino:   "01310100",
          weight_grams:  150,
          service_codes: [ "03220", "03298" ]
        )

        assert_equal 2, rows.length
        assert_equal "19,84", rows.first["pcFinal"]

        assert_requested(:post, URL) do |req|
          headers = req.headers
          body    = JSON.parse(req.body)
          assert_equal "Bearer test-api", headers["Authorization"]
          assert_equal "application/json", headers["Accept"]
          assert_equal 2, body["parametrosProduto"].length
          first = body["parametrosProduto"].first
          assert_equal "03220", first["coProduto"]
          assert_equal "03220", first["nuRequisicao"]
          assert_equal "37600000", first["cepOrigem"]
          assert_equal "01310100", first["cepDestino"]
          assert_equal "150", first["psObjeto"]
          assert_equal "2", first["tpObjeto"]
          assert_equal "24", first["comprimento"]
          assert_equal "16", first["largura"]
          assert_equal "4",  first["altura"]
          assert_match(/\d{2}\/\d{2}\/\d{4}/, first["dtEvento"])
          true
        end
      end

      test "returns the response array verbatim (eligibility lives in the domain)" do
        # Mini Envios requested → coProduto swapped to 04960 because the package
        # exceeds the 300g limit. The wrapper doesn't filter; Shipping::Quote does.
        stub_request(:post, URL).to_return(status: 200,
          body: [ { "coProduto" => "04960", "nuRequisicao" => "04227", "pcFinal" => "18,08" } ].to_json,
          headers: { "Content-Type" => "application/json" })

        rows = Correios::Api::Preco.fetch(
          cep_origem: "37600000", cep_destino: "01310100",
          weight_grams: 350, service_codes: [ "04227" ]
        )

        assert_equal "04960", rows.first["coProduto"]
        assert_equal "04227", rows.first["nuRequisicao"]
      end

      test "raises InvalidObjectError on a 400 (bad CEP / invalid contract)" do
        stub_request(:post, URL).to_return(status: 400, body: "{}")

        assert_raises(Correios::Api::InvalidObjectError) do
          Correios::Api::Preco.fetch(cep_origem: "37600000", cep_destino: "00000000",
                                     weight_grams: 100, service_codes: [ "03220" ])
        end
      end

      test "raises TransientError on a 429" do
        stub_request(:post, URL).to_return(status: 429, body: "slow")
        assert_raises(Correios::Api::TransientError) do
          Correios::Api::Preco.fetch(cep_origem: "37600000", cep_destino: "01310100",
                                     weight_grams: 100, service_codes: [ "03220" ])
        end
      end

      test "raises TransientError on a 503" do
        stub_request(:post, URL).to_return(status: 503, body: "down")
        assert_raises(Correios::Api::TransientError) do
          Correios::Api::Preco.fetch(cep_origem: "37600000", cep_destino: "01310100",
                                     weight_grams: 100, service_codes: [ "03220" ])
        end
      end

      test "raises TransientError on a timeout" do
        stub_request(:post, URL).to_timeout
        assert_raises(Correios::Api::TransientError) do
          Correios::Api::Preco.fetch(cep_origem: "37600000", cep_destino: "01310100",
                                     weight_grams: 100, service_codes: [ "03220" ])
        end
      end

      test "raises Error when the body is not JSON" do
        stub_request(:post, URL).to_return(status: 200, body: "<html>nope</html>")
        error = assert_raises(Correios::Api::Error) do
          Correios::Api::Preco.fetch(cep_origem: "37600000", cep_destino: "01310100",
                                     weight_grams: 100, service_codes: [ "03220" ])
        end
        refute_kind_of Correios::Api::TransientError,     error
        refute_kind_of Correios::Api::InvalidObjectError, error
      end

      test "treats an empty 200 body as an empty array" do
        stub_request(:post, URL).to_return(status: 200, body: "")
        assert_equal [], Correios::Api::Preco.fetch(
          cep_origem: "37600000", cep_destino: "01310100",
          weight_grams: 100, service_codes: [ "03220" ]
        )
      end
    end
  end
end
