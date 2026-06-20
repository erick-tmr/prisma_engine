require "test_helper"

# End-to-end: a pré-postagem shipment exists, the hourly orchestrator fans out a
# per-shipment sync, and the rastro response drives the shipment to delivered.
class CorreiosPollingFlowTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  BASE = Correios::Api::BASE_URL

  setup do
    @prev_token = ENV["CORREIOS_API_TOKEN"]
    ENV["CORREIOS_API_TOKEN"] = "test-token"
  end

  teardown do
    ENV["CORREIOS_API_TOKEN"] = @prev_token
  end

  test "pré-postagem then polling delivers the shipment and records its events" do
    shipment = orders(:awaiting).shipment
    Shipping::ShipmentFactory.update_from_pre_postagem(shipment, pre_post_payload)
    code = shipment.reload.tracking_code

    stub_request(:get, "#{BASE}/srorastro/v1/objetos/#{code}?resultado=T")
      .to_return(status: 200, body: rastro_body(code),
                 headers: { "Content-Type" => "application/json" })

    perform_enqueued_jobs do
      SyncPendingShipmentsJob.perform_now
    end

    shipment.reload
    assert shipment.tracking_delivered?
    assert_equal "Objeto entregue ao destinatário", shipment.last_tracking_status
    assert_equal %w[PO BDE], shipment.tracking_events.order(:position).map(&:event_code)
  end

  private

  def pre_post_payload
    {
      "id" => "PR123",
      "codigoObjeto" => "AD483393343BR",
      "codigoServico" => "03220",
      "statusAtual" => 3,
      "descStatusAtual" => "Postado"
    }
  end

  def rastro_body(code)
    {
      "objetos" => [
        {
          "codObjeto" => code,
          "eventos" => [
            { "codigo" => "BDE", "tipo" => "01", "dtHrCriado" => "2026-05-23T10:58:58",
              "descricao" => "Objeto entregue ao destinatário" },
            { "codigo" => "PO", "tipo" => "01", "dtHrCriado" => "2026-05-22T14:51:02",
              "descricao" => "Objeto postado" }
          ]
        }
      ]
    }.to_json
  end
end
