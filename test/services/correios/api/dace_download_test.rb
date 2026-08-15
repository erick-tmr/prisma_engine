require "test_helper"

module Correios
  module Api
    class DaceDownloadTest < ActiveSupport::TestCase
      BASE = Correios::Api::BASE_URL
      URL = "#{BASE}/prepostagem/v1/prepostagens/dce/dace/impressao".freeze
      PRE_POST = "PR-abc".freeze
      JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

      def fetch(id = PRE_POST)
        Correios::Api.stub(:cartao_api_token, "test-token") { Correios::Api::DaceDownload.fetch(id) }
      end

      def stub_dace(status:, body:)
        stub_request(:post, URL).to_return(status: status, body: body, headers: JSON_HEADERS)
      end

      test "asks for one pré-postagem as PDF and returns the parsed body" do
        stub_dace(status: 200, body: { "objetos" => [ PRE_POST ], "dados" => "JVBERi0=" }.to_json)

        assert_equal({ "objetos" => [ PRE_POST ], "dados" => "JVBERi0=" }, fetch)

        assert_requested :post, URL, headers: { "Authorization" => "Bearer test-token" } do |request|
          JSON.parse(request.body) == { "idsPrePostagens" => [ PRE_POST ], "tipoDace" => "C" }
        end
      end

      test "a 404 naming the PPN code raises a definitive error carrying the reason" do
        stub_dace(status: 404, body: { "msgs" => [ "PPN-376: Não é possível emitir DACE para NF-e." ] }.to_json)

        error = assert_raises(Correios::Api::Error) { fetch }

        assert_match "PPN-376", error.message
        assert_match PRE_POST, error.message
        refute_kind_of Correios::Api::TransientError, error
      end

      test "a 400 for a missing id is definitive too" do
        stub_dace(status: 400, body: { "msgs" => [ "PPN-375: É obrigatório informar ao menos um idPrePostagem." ] }.to_json)

        error = assert_raises(Correios::Api::Error) { fetch }

        assert_match "PPN-375", error.message
        refute_kind_of Correios::Api::TransientError, error
      end

      test "a 500 is transient so the step retries" do
        stub_dace(status: 500, body: { "msgs" => [ "boom" ] }.to_json)

        assert_raises(Correios::Api::TransientError) { fetch }
      end

      test "a 5xx with no readable message still falls through to the shared guard" do
        stub_dace(status: 503, body: "gateway down")

        assert_raises(Correios::Api::TransientError) { fetch }
      end

      test "a 4xx with no readable message raises a plain error" do
        stub_dace(status: 422, body: "nope")

        error = assert_raises(Correios::Api::Error) { fetch }
        refute_kind_of Correios::Api::TransientError, error
      end

      test "a timeout is transient" do
        stub_request(:post, URL).to_timeout

        assert_raises(Correios::Api::TransientError) { fetch }
      end
    end
  end
end
