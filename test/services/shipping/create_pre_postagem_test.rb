require "test_helper"

module Shipping
  class CreatePrePostagemTest < ActiveSupport::TestCase
    BASE = Correios::Api::BASE_URL
    URL = "#{BASE}/prepostagem/v1/prepostagens".freeze

    setup do
      @shipment = shipments(:awaiting)
    end

    test "creates a pré-postagem and updates the shipment with the Correios response" do
      stub_create(status: 201)

      shipment = Shipping::CreatePrePostagem.call(request_for(:sedex), shipment: @shipment)

      assert_equal @shipment, shipment
      assert_equal "AD515656026BR", shipment.reload.tracking_code
      assert_equal "PRHelX4tO8Qsuqq0D47quwxA", shipment.pre_post_id
      assert_equal "03220", shipment.service_code
      assert_equal 1, shipment.correios_status
    end

    test "maps the service name to its codigoServico and requires a known one" do
      assert_equal "03220", Shipping::SERVICES.fetch(:sedex)
      assert_raises(KeyError) { Shipping::CreatePrePostagem.call(request_for(:fedex), shipment: @shipment) }
    end

    test "sends the hardcoded store sender, card number and policy flags" do
      stub_create(status: 201)

      Shipping::CreatePrePostagem.call(request_for(:sedex), shipment: @shipment)

      assert_equal "Prisma Games", @sent.dig("remetente", "nome")
      assert_equal "0076738043", @sent["numeroCartaoPostagem"]
      assert_equal "03220", @sent["codigoServico"]
      assert_equal "2", @sent["codigoFormatoObjetoInformado"]
      assert_equal "1", @sent["cienteObjetoNaoProibido"]
      assert_equal "N", @sent["solicitarColeta"]
      assert_equal "N", @sent["logisticaReversa"]
      assert_equal "S", @sent["emiteDCe"]
      assert_equal "120", @sent["pesoInformado"]
    end

    test "the recipient and dimensions come from the shipment snapshot" do
      stub_create(status: 201)

      Shipping::CreatePrePostagem.call(request_for(:pac), shipment: @shipment)

      assert_equal "Cliente Confirmado", @sent.dig("destinatario", "nome")
      assert_equal "01310100", @sent.dig("destinatario", "endereco", "cep")
    end

    test "a pré-postagem with no codigoObjeto fails non-retryably, keeping the payload for review" do
      stub_create(status: 201, codigo_objeto: nil)

      error = assert_raises(Correios::Api::InvalidObjectError) do
        Shipping::CreatePrePostagem.call(request_for(:sedex), shipment: @shipment)
      end

      assert_match(/came back without codigoObjeto/, error.message)
      assert_not_kind_of Correios::Api::TransientError, error, "must not be retried into a duplicate"

      @shipment.reload
      assert_nil @shipment.tracking_code
      assert_equal "PRHelX4tO8Qsuqq0D47quwxA", @shipment.pre_post_id, "manual review needs the id"
      assert_equal "PRHelX4tO8Qsuqq0D47quwxA", @shipment.pre_post_payload["id"], "and the full response"
    end

    test "an empty codigoObjeto is rejected the same way as a null one" do
      stub_create(status: 201, codigo_objeto: "")

      assert_raises(Correios::Api::InvalidObjectError) do
        Shipping::CreatePrePostagem.call(request_for(:sedex), shipment: @shipment)
      end
    end

    test "a codigoObjeto Correios omitted entirely fails in our own vocabulary, not with a KeyError" do
      stub_raw({ "id" => "PRHelX4tO8Qsuqq0D47quwxA", "codigoServico" => "03220" })

      error = assert_raises(Correios::Api::InvalidObjectError) do
        Shipping::CreatePrePostagem.call(request_for(:sedex), shipment: @shipment)
      end

      assert_match(/came back without codigoObjeto/, error.message)
      assert_equal "PRHelX4tO8Qsuqq0D47quwxA", @shipment.reload.pre_post_id, "manual review needs the id"
    end

    test "a pré-postagem with no id is rejected too: nothing can request a rótulo for it" do
      stub_raw({ "codigoObjeto" => "AD515656026BR", "codigoServico" => "03220" })

      error = assert_raises(Correios::Api::InvalidObjectError) do
        Shipping::CreatePrePostagem.call(request_for(:sedex), shipment: @shipment)
      end

      assert_match(/came back without id/, error.message)
      assert_equal({ "codigoObjeto" => "AD515656026BR", "codigoServico" => "03220" },
                   @shipment.reload.pre_post_payload, "the raw response is what review has to go on")
    end

    test "a response missing both fields names both, and leaves the columns null so a retry can still pin" do
      stub_raw({ "codigoServico" => "03220" })

      error = assert_raises(Correios::Api::InvalidObjectError) do
        Shipping::CreatePrePostagem.call(request_for(:sedex), shipment: @shipment)
      end

      assert_match(/came back without codigoObjeto and id/, error.message)
      @shipment.reload
      assert_nil @shipment.tracking_code
      assert_nil @shipment.pre_post_id, "an empty string here would pin the row to junk"
    end

    test "a duplicate whose payload lacks the code keeps the pinned original and does not fail" do
      @shipment.update!(tracking_code: "AD515656026BR", pre_post_id: "PRoriginal000000000000000")
      stub_create(status: 201, codigo_objeto: nil)

      shipment = Shipping::CreatePrePostagem.call(request_for(:sedex), shipment: @shipment)

      assert_equal "AD515656026BR", shipment.reload.tracking_code
      assert_equal "PRoriginal000000000000000", shipment.pre_post_id
    end

    private

    def request_for(service)
      Shipping::PrePostagemRequest.from_shipment(@shipment).with(service: service)
    end

    def stub_raw(body)
      stub_request(:post, URL).to_return(
        status: 201, body: body.to_json, headers: { "Content-Type" => "application/json" }
      )
    end

    def stub_create(status:, service: "03220", codigo_objeto: "AD515656026BR")
      stub_request(:post, URL)
        .with { |request| @sent = JSON.parse(request.body); true }
        .to_return(
          status: status,
          body: response_body(service: service, codigo_objeto: codigo_objeto),
          headers: { "Content-Type" => "application/json" }
        )
    end

    def response_body(service:, codigo_objeto: "AD515656026BR")
      {
        "id" => "PRHelX4tO8Qsuqq0D47quwxA",
        "codigoObjeto" => codigo_objeto,
        "codigoServico" => service,
        "statusAtual" => 1,
        "descStatusAtual" => "Pré-atendido",
        "dataHora" => "2026-06-04T10:00:00",
        "prazoPostagem" => "2026-06-18T23:59:59"
      }.to_json
    end
  end
end
