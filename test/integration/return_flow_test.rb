require "test_helper"

class ReturnFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  BASE = Correios::Api::BASE_URL
  PREPOST = "#{BASE}/prepostagem/v1/prepostagens".freeze
  ROTULO = "#{BASE}/prepostagem/v1/prepostagens/rotulo/assincrono/pdf".freeze
  RECIBO = "recibo-devolucao".freeze
  DOWNLOAD = "#{BASE}/prepostagem/v1/prepostagens/rotulo/download/assincrono/#{RECIBO}".freeze
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  setup { @order = orders(:delivered) }

  test "the customer is the remetente and the store the destinatario" do
    stub_all

    perform_enqueued_jobs { Shipping::AuthorizeReturn.call(order: @order) }

    body = nil
    assert_requested(:post, PREPOST, times: 1) { |request| body = JSON.parse(request.body) }

    assert_equal @order.shipment.receiver_name, body.dig("remetente", "nome")
    assert_equal @order.shipment.zip, body.dig("remetente", "endereco", "cep")
    assert_equal Shipping::STORE[:nome], body.dig("destinatario", "nome")
    assert_equal Shipping::ORIGIN_CEP, body.dig("destinatario", "endereco", "cep")
    assert_equal "N", body["logisticaReversa"]
    assert_equal Shipping::POSTAGE_CARD_NUMBER, body["numeroCartaoPostagem"]
    assert_equal "#{@order.number} DEVOLUCAO", body["observacao"]
  end

  test "the return label runs the whole saga without touching the outbound leg" do
    stub_all
    outbound_code = @order.shipment.tracking_code

    perform_enqueued_jobs { Shipping::AuthorizeReturn.call(order: @order) }

    @order.reload
    assert @order.awaiting_return?, "the label being ready must not move the return leg on its own"
    assert @order.return_shipping_label.ready?
    assert_equal "AR111111111BR", @order.return_shipment.tracking_code
    assert_equal outbound_code, @order.shipment.reload.tracking_code
    assert_nil @order.shipping_label
  end

  test "correios tracking walks the order from awaiting_return to returned" do
    stub_all
    perform_enqueued_jobs { Shipping::AuthorizeReturn.call(order: @order) }
    inbound = @order.reload.return_shipment

    Shipping::TrackingUpdate.apply(inbound, [ event("PO", "01", "Objeto postado") ])
    Shipping::OrderProgress.apply(inbound.reload)
    assert @order.reload.returning?

    Shipping::TrackingUpdate.apply(inbound, [ event("PO", "01", "Objeto postado"),
                                              event("BDE", "01", "Objeto entregue") ])
    Shipping::OrderProgress.apply(inbound.reload)
    assert @order.reload.returned?
  end

  test "each step of the return leg mails the customer once" do
    stub_all
    perform_enqueued_jobs { Shipping::AuthorizeReturn.call(order: @order) }
    inbound = @order.reload.return_shipment

    assert_enqueued_email_with OrderMailer, :returning, args: [ @order ] do
      Shipping::TrackingUpdate.apply(inbound, [ event("PO", "01", "Objeto postado") ])
      Shipping::OrderProgress.apply(inbound.reload)
    end
  end

  private

  def event(code, type, description)
    { code: code, type: type, description: description, occurred_at: Time.current, payload: {} }
  end

  def stub_all
    stub_request(:post, PREPOST).to_return(
      status: 201,
      body: { "id" => "PR-devolucao", "codigoObjeto" => "AR111111111BR", "codigoServico" => "03298",
              "statusAtual" => 1, "descStatusAtual" => "Pré-atendido",
              "dataHora" => "2026-06-20T10:00:00", "prazoPostagem" => "2026-07-04T23:59:59" }.to_json,
      headers: JSON_HEADERS
    )
    stub_request(:get, %r{/prepostagem/v2/prepostagens}).to_return(
      status: 200,
      body: { "itens" => [ { "codigoObjeto" => "AR111111111BR", "statusAtual" => 2,
                            "descStatusAtual" => "Pré-postado",
                            "dataHoraStatusAtual" => "2026-06-20T10:00:01" } ] }.to_json,
      headers: JSON_HEADERS
    )
    stub_request(:post, ROTULO).to_return(
      status: 200, body: { "idRecibo" => RECIBO }.to_json, headers: JSON_HEADERS
    )
    stub_request(:get, DOWNLOAD).to_return(
      status: 200,
      body: { "nome" => "devolucao.pdf", "dados" => Base64.strict_encode64("%PDF-1.4 devolucao") }.to_json,
      headers: JSON_HEADERS
    )
  end
end
