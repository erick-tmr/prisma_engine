require "test_helper"

class EmitLabelFlowTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  BASE = Correios::Api::BASE_URL
  PREPOST = "#{BASE}/prepostagem/v1/prepostagens".freeze
  ROTULO = "#{BASE}/prepostagem/v1/prepostagens/rotulo/assincrono/pdf".freeze
  RECIBO = "recibo-123".freeze
  DOWNLOAD = "#{BASE}/prepostagem/v1/prepostagens/rotulo/download/assincrono/#{RECIBO}".freeze
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  setup do
    @prev_token = ENV["CORREIOS_CARTAO_API_TOKEN"]
    ENV["CORREIOS_CARTAO_API_TOKEN"] = "test-token"
    @order = orders(:producing)
  end

  teardown do
    ENV["CORREIOS_CARTAO_API_TOKEN"] = @prev_token
  end

  test "runs the full saga and moves the order to label_issued with a stored PDF" do
    stub_prepostagem
    stub_status(2)
    stub_rotulo
    stub_download

    perform_enqueued_jobs { Shipping::EmitLabel.resume(@order) }

    @order.reload
    label = @order.shipment.shipping_label
    assert label.ready?
    assert_equal RECIBO, label.recibo_id
    assert_equal "etiqueta.pdf", label.filename
    assert_equal "%PDF-1.4 fake", label.pdf_bytes
    assert @order.label_issued?
    assert_equal "AD999999999BR", @order.shipment.tracking_code
  end

  test "resumes from the failed step without redoing completed steps" do
    stub_prepostagem
    stub_status(2)
    stub_request(:post, ROTULO).to_return(status: 400, body: "bad request")

    @order.shipment.create_shipping_label!
    Shipping::CreatePrePostagemJob.perform_now(@order.id)
    Shipping::ConfirmPrePostagemJob.perform_now(@order.id)
    label = @order.shipment.shipping_label
    assert label.reload.prepost_confirmed?

    assert_raises(Correios::Api::Error) { Shipping::RequestLabelJob.perform_now(@order.id) }
    assert label.reload.error.present?
    assert_requested :post, PREPOST, times: 1
    clear_enqueued_jobs

    stub_rotulo
    stub_download
    perform_enqueued_jobs { Shipping::EmitLabel.resume(@order) }

    assert @order.reload.label_issued?
    assert @order.shipment.shipping_label.ready?
    assert_requested :post, PREPOST, times: 1
  end

  private

  def stub_prepostagem
    stub_request(:post, PREPOST).to_return(status: 201, body: prepost_body, headers: JSON_HEADERS)
  end

  def stub_status(status)
    stub_request(:get, %r{/prepostagem/v2/prepostagens}).to_return(
      status: 200,
      body: { "itens" => [ { "codigoObjeto" => "AD999999999BR", "statusAtual" => status,
                            "descStatusAtual" => "Pré-postado",
                            "dataHoraStatusAtual" => "2026-06-20T10:00:01" } ] }.to_json,
      headers: JSON_HEADERS
    )
  end

  def stub_rotulo
    stub_request(:post, ROTULO).to_return(
      status: 200, body: { "idRecibo" => RECIBO }.to_json, headers: JSON_HEADERS
    )
  end

  def stub_download
    stub_request(:get, DOWNLOAD).to_return(
      status: 200,
      body: { "nome" => "etiqueta.pdf", "dados" => Base64.strict_encode64("%PDF-1.4 fake") }.to_json,
      headers: JSON_HEADERS
    )
  end

  def prepost_body
    {
      "id" => "PR-abc",
      "codigoObjeto" => "AD999999999BR",
      "codigoServico" => "03298",
      "statusAtual" => 1,
      "descStatusAtual" => "Pré-atendido",
      "dataHora" => "2026-06-20T10:00:00",
      "prazoPostagem" => "2026-07-04T23:59:59"
    }.to_json
  end
end
