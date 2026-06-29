require "test_helper"

module Correios
  module Api
    class RotuloDownloadTest < ActiveSupport::TestCase
      BASE = Correios::Api::BASE_URL
      RECIBO = "R-123".freeze
      URL = "#{BASE}/prepostagem/v1/prepostagens/rotulo/download/assincrono/#{RECIBO}".freeze

      test "GETs the recibo with the cartão bearer token and returns the parsed response" do
        stub_request(:get, URL).to_return(
          status: 200, body: { "nome" => "label.pdf", "dados" => "JVBERi0=" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

        response = Correios::Api.stub(:cartao_api_token, "test-token") do
          Correios::Api::RotuloDownload.fetch(RECIBO)
        end

        assert_equal "label.pdf", response["nome"]
        assert_equal "JVBERi0=", response["dados"]
        assert_requested :get, URL, headers: { "Authorization" => "Bearer test-token" }
      end

      test "raises TransientError on a 500" do
        stub_request(:get, URL).to_return(status: 500, body: "boom")

        assert_raises(Correios::Api::TransientError) { Correios::Api::RotuloDownload.fetch(RECIBO) }
      end

      test "raises a non-transient Error on a 404" do
        stub_request(:get, URL).to_return(status: 404, body: "not found")

        error = assert_raises(Correios::Api::Error) { Correios::Api::RotuloDownload.fetch(RECIBO) }
        refute_kind_of Correios::Api::TransientError, error
      end

      test "raises TransientError on a timeout" do
        stub_request(:get, URL).to_timeout

        assert_raises(Correios::Api::TransientError) { Correios::Api::RotuloDownload.fetch(RECIBO) }
      end

      test "raises a non-transient Error when a 200 carries a message instead of the label" do
        stub_request(:get, URL).to_return(
          status: 200,
          body: { "mensagem" => "PPN-288: status igual a Pendente" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

        error = assert_raises(Correios::Api::Error) { Correios::Api::RotuloDownload.fetch(RECIBO) }
        refute_kind_of Correios::Api::TransientError, error
        assert_match "PPN-288", error.message
      end

      test "raises a non-transient Error when the 200 body is not a label object" do
        stub_request(:get, URL).to_return(
          status: 200, body: "[]", headers: { "Content-Type" => "application/json" }
        )

        assert_raises(Correios::Api::Error) { Correios::Api::RotuloDownload.fetch(RECIBO) }
      end
    end
  end
end
