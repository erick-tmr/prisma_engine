require "test_helper"

module Correios
  module Api
    class PrePostagemStatusTest < ActiveSupport::TestCase
      BASE = Correios::Api::BASE_URL
      CODE = "AD601193771BR".freeze
      URL = "#{BASE}/prepostagem/v2/prepostagens?codigoObjeto=#{CODE}".freeze

      test "returns the first item with the cartão bearer token" do
        stub_status(status: 200, body: { "itens" => [ item ], "page" => {} }.to_json)

        result = Correios::Api.stub(:cartao_api_token, "test-token") do
          Correios::Api::PrePostagemStatus.fetch(CODE)
        end

        assert_requested :get, URL,
          headers: { "Authorization" => "Bearer test-token", "Accept" => "application/json" }
        assert_equal 2, result["statusAtual"]
        assert_equal CODE, result["codigoObjeto"]
      end

      test "returns nil when no item matches yet" do
        stub_status(status: 200, body: { "itens" => [], "page" => {} }.to_json)

        assert_nil Correios::Api::PrePostagemStatus.fetch(CODE)
      end

      test "raises TransientError on a 500" do
        stub_status(status: 500, body: "boom")

        assert_raises(Correios::Api::TransientError) { Correios::Api::PrePostagemStatus.fetch(CODE) }
      end

      test "raises TransientError on a 429" do
        stub_status(status: 429, body: "slow down")

        assert_raises(Correios::Api::TransientError) { Correios::Api::PrePostagemStatus.fetch(CODE) }
      end

      test "raises a non-transient Error on a 401" do
        stub_status(status: 401, body: "unauthorized")

        error = assert_raises(Correios::Api::Error) { Correios::Api::PrePostagemStatus.fetch(CODE) }
        refute_kind_of Correios::Api::TransientError, error
      end

      test "raises TransientError on a timeout" do
        stub_request(:get, %r{/prepostagem/v2/prepostagens}).to_timeout

        assert_raises(Correios::Api::TransientError) { Correios::Api::PrePostagemStatus.fetch(CODE) }
      end

      test "raises a non-transient Error when the 200 body is not JSON" do
        stub_status(status: 200, body: "<html>not json</html>")

        error = assert_raises(Correios::Api::Error) { Correios::Api::PrePostagemStatus.fetch(CODE) }
        refute_kind_of Correios::Api::TransientError, error
      end

      private

      def stub_status(status:, body:)
        stub_request(:get, URL)
          .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
      end

      def item
        {
          "codigoObjeto" => CODE,
          "statusAtual" => 2,
          "descStatusAtual" => "Pré-postado",
          "dataHoraStatusAtual" => "2026-06-22T20:00:34.711579"
        }
      end
    end
  end
end
