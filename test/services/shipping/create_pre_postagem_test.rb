require "test_helper"

module Shipping
  class CreatePrePostagemTest < ActiveSupport::TestCase
    BASE = Correios::Api::BASE_URL
    URL = "#{BASE}/prepostagem/v1/prepostagens".freeze

    setup do
      @prev_token = ENV["CORREIOS_CARTAO_API_TOKEN"]
      ENV["CORREIOS_CARTAO_API_TOKEN"] = "test-token"
      @shipment = shipments(:awaiting)
    end

    teardown do
      ENV["CORREIOS_CARTAO_API_TOKEN"] = @prev_token
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

    private

    def request_for(service)
      Shipping::PrePostagemRequest.from_shipment(@shipment).with(service: service)
    end

    def stub_create(status:, service: "03220")
      stub_request(:post, URL)
        .with { |request| @sent = JSON.parse(request.body); true }
        .to_return(
          status: status,
          body: response_body(service: service),
          headers: { "Content-Type" => "application/json" }
        )
    end

    def response_body(service:)
      {
        "id" => "PRHelX4tO8Qsuqq0D47quwxA",
        "codigoObjeto" => "AD515656026BR",
        "codigoServico" => service,
        "statusAtual" => 1,
        "descStatusAtual" => "Pré-atendido",
        "dataHora" => "2026-06-04T10:00:00",
        "prazoPostagem" => "2026-06-18T23:59:59"
      }.to_json
    end
  end
end
