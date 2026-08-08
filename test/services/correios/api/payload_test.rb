require "test_helper"

module Correios
  module Api
    class PayloadTest < ActiveSupport::TestCase
      CONTEXT = "pré-postagem PR-1".freeze

      test "hash passes a Hash through and swaps anything else for an empty one" do
        assert_equal({ "a" => 1 }, Payload.hash({ "a" => 1 }))
        assert_equal({}, Payload.hash(nil))
        assert_equal({}, Payload.hash([ "objetos" ]))
        assert_equal({}, Payload.hash("erro"))
      end

      test "string collapses absent, null and blank onto the same empty string" do
        assert_equal "", Payload.string({}, "codigoObjeto")
        assert_equal "", Payload.string({ "codigoObjeto" => nil }, "codigoObjeto")
        assert_equal "", Payload.string({ "codigoObjeto" => "" }, "codigoObjeto")
        assert_equal "", Payload.string({ "codigoObjeto" => "   " }, "codigoObjeto")
        assert_equal "", Payload.string(nil, "codigoObjeto")
      end

      test "string trims and stringifies whatever Correios actually sent" do
        assert_equal "AD515656026BR", Payload.string({ "codigoObjeto" => " AD515656026BR " }, "codigoObjeto")
        assert_equal "2", Payload.string({ "statusAtual" => 2 }, "statusAtual")
      end

      test "require_string returns the value when Correios sent one" do
        assert_equal "REC-9", Payload.require_string({ "idRecibo" => "REC-9" }, "idRecibo", CONTEXT)
      end

      test "require_string rejects absent, null and blank alike, naming the field" do
        [ {}, { "idRecibo" => nil }, { "idRecibo" => "" }, { "idRecibo" => " " } ].each do |body|
          error = assert_raises(Correios::Api::InvalidObjectError) do
            Payload.require_string(body, "idRecibo", CONTEXT)
          end

          assert_equal "#{CONTEXT}: idRecibo came back empty", error.message
          assert_not_kind_of Correios::Api::TransientError, error, "a hollow field must not be retried"
        end
      end

      test "integer parses digits and refuses anything that is not a whole number" do
        assert_equal 2, Payload.integer({ "statusAtual" => 2 }, "statusAtual")
        assert_equal 2, Payload.integer({ "statusAtual" => "2" }, "statusAtual")
        assert_nil Payload.integer({ "statusAtual" => nil }, "statusAtual")
        assert_nil Payload.integer({}, "statusAtual")
        assert_nil Payload.integer({ "statusAtual" => "pendente" }, "statusAtual")
        assert_nil Payload.integer({ "statusAtual" => "2.5" }, "statusAtual")
      end

      test "decimal accepts the Brazilian comma Correios quotes prices with" do
        assert_in_delta 24.9, Payload.decimal({ "pcFinal" => "24,90" }, "pcFinal")
        assert_in_delta 24.9, Payload.decimal({ "pcFinal" => "24.90" }, "pcFinal")
        assert_nil Payload.decimal({ "pcFinal" => "" }, "pcFinal")
        assert_nil Payload.decimal({ "pcFinal" => "grátis" }, "pcFinal")
      end

      test "time parses a Brasília timestamp and shrugs off a missing one" do
        parsed = Payload.time({ "dataHora" => "2026-06-20T10:00:00" }, "dataHora")

        assert_equal Correios::Api::Timestamp.parse("2026-06-20T10:00:00"), parsed
        assert_nil Payload.time({ "dataHora" => nil }, "dataHora")
        assert_nil Payload.time({}, "dataHora")
      end
    end
  end
end
