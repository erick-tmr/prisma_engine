require "test_helper"

module Correios
  module Api
    class TrackingTest < ActiveSupport::TestCase
      BASE = Correios::Api::BASE_URL
      CODE = "AD483393343BR".freeze

      test "returns events oldest-first, normalized, with the bearer token" do
        stub_objetos(status: 200, body: sample_body)

        events = Correios::Api.stub(:api_token, "test-token") do
          Correios::Api::Tracking.fetch(CODE)
        end

        assert_requested :get, "#{BASE}/srorastro/v1/objetos/#{CODE}?resultado=T",
          headers: { "Authorization" => "Bearer test-token", "Accept" => "application/json" }

        # Response is newest-first (BDE … FC); we hand it back oldest-first.
        assert_equal %w[FC PO BDE], events.map { |event| event[:code] }

        delivered = events.last
        assert_equal "01", delivered[:type]
        assert_equal "Objeto entregue ao destinatário", delivered[:description]
        # 2026-05-23T10:58:58 Brasília (-03:00) == 13:58:58 UTC
        assert_equal Time.utc(2026, 5, 23, 13, 58, 58), delivered[:occurred_at]
        assert_equal "BDE", delivered[:payload]["codigo"]
      end

      test "orders events by dtHrCriado regardless of array order; timeless first" do
        body = {
          "objetos" => [ {
            "codObjeto" => CODE,
            "eventos" => [
              event("BDE", "01", "2026-05-23T10:58:58", "entregue"),
              { "codigo" => "ZZ", "tipo" => "00", "descricao" => "no timestamp" },
              event("PO", "01", "2026-05-22T14:51:02", "postado")
            ]
          } ]
        }.to_json
        stub_objetos(status: 200, body: body)

        events = Correios::Api::Tracking.fetch(CODE)

        # The timestamp-less event sorts first (epoch); the rest are chronological.
        assert_equal %w[ZZ PO BDE], events.map { |event| event[:code] }
        assert_nil events.first[:occurred_at]
      end

      test "returns [] when the object carries no events" do
        stub_objetos(
          status: 200,
          body: { "objetos" => [ { "codObjeto" => CODE, "mensagem" => "SRO-020" } ] }.to_json
        )

        assert_empty Correios::Api::Tracking.fetch(CODE)
      end

      test "raises TransientError on a 500" do
        stub_objetos(status: 500, body: "boom")

        assert_raises(Correios::Api::TransientError) { Correios::Api::Tracking.fetch(CODE) }
      end

      test "raises TransientError on a 429" do
        stub_objetos(status: 429, body: "slow down")

        assert_raises(Correios::Api::TransientError) { Correios::Api::Tracking.fetch(CODE) }
      end

      test "raises a non-transient Error on a 401" do
        stub_objetos(status: 401, body: "unauthorized")

        error = assert_raises(Correios::Api::Error) { Correios::Api::Tracking.fetch(CODE) }
        refute_kind_of Correios::Api::TransientError, error
      end

      test "raises TransientError on a timeout" do
        stub_request(:get, %r{/srorastro/v1/objetos/#{CODE}}).to_timeout

        assert_raises(Correios::Api::TransientError) { Correios::Api::Tracking.fetch(CODE) }
      end

      test "raises a non-transient Error when the 200 body is not JSON" do
        stub_objetos(status: 200, body: "<html>not json</html>")

        error = assert_raises(Correios::Api::Error) { Correios::Api::Tracking.fetch(CODE) }
        refute_kind_of Correios::Api::TransientError, error
      end

      test "raises InvalidObjectError on a 200 carrying SRO-019 (invalid object)" do
        stub_objetos(
          status: 200,
          body: { "objetos" => [ { "codObjeto" => CODE, "mensagem" => "SRO-019: Objeto inválido" } ] }.to_json
        )

        assert_raises(Correios::Api::InvalidObjectError) { Correios::Api::Tracking.fetch(CODE) }
      end

      private

      def stub_objetos(status:, body:)
        stub_request(:get, "#{BASE}/srorastro/v1/objetos/#{CODE}?resultado=T")
          .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
      end

      def sample_body
        {
          "versao" => "3.4.25",
          "quantidade" => 1,
          "objetos" => [
            {
              "codObjeto" => CODE,
              "eventos" => [
                event("BDE", "01", "2026-05-23T10:58:58", "Objeto entregue ao destinatário"),
                event("PO", "01", "2026-05-22T14:51:02", "Objeto postado"),
                event("FC", "82", "2026-05-22T13:11:04", "Etiqueta emitida")
              ]
            }
          ]
        }.to_json
      end

      def event(codigo, tipo, dt, descricao)
        { "codigo" => codigo, "tipo" => tipo, "dtHrCriado" => dt, "descricao" => descricao }
      end
    end
  end
end
