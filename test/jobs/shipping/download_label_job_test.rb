require "test_helper"

module Shipping
  class DownloadLabelJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    BASE = Correios::Api::BASE_URL
    RECIBO = "R-42".freeze
    URL = "#{BASE}/prepostagem/v1/prepostagens/rotulo/download/assincrono/#{RECIBO}".freeze

    setup do
      @order = orders(:producing)
      @label = @order.shipment.create_shipping_label!(state: :requested, recibo_id: RECIBO)
    end

    test "downloads the PDF, marks the label ready and moves the order to label_issued" do
      stub_request(:get, URL).to_return(
        status: 200,
        body: { "nome" => "etiqueta.pdf", "dados" => Base64.strict_encode64("%PDF-1.4") }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      Shipping::DownloadLabelJob.perform_now(shipment_id: @order.shipment.id)

      assert @label.reload.ready?
      assert_equal "etiqueta.pdf", @label.filename
      assert_equal "%PDF-1.4", @label.pdf_bytes
      assert @order.reload.label_issued?
    end

    test "on PPN-295 it rewinds the label and re-requests a fresh recibo" do
      stub_request(:get, URL).to_return(
        status: 200,
        body: { "mensagem" => "PPN-295: Houve uma falha na geração do rótulo. Gere um novo recibo." }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      assert_enqueued_with(job: Shipping::RequestLabelJob, args: [ { shipment_id: @order.shipment.id } ]) do
        Shipping::DownloadLabelJob.perform_now(shipment_id: @order.shipment.id)
      end

      assert @label.reload.prepost_confirmed?
      assert_nil @label.recibo_id
      assert_equal 1, @label.relabel_attempts
      assert @order.reload.in_production?
    end

    test "on PPN-295 past the relabel cap it records the error and stops" do
      @label.update!(relabel_attempts: Shipping::LabelStep::MAX_RELABEL_ATTEMPTS)
      stub_request(:get, URL).to_return(
        status: 200,
        body: { "mensagem" => "PPN-295: Houve uma falha na geração do rótulo. Gere um novo recibo." }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      assert_no_enqueued_jobs do
        assert_raises(Correios::Api::LabelGenerationFailedError) { Shipping::DownloadLabelJob.perform_now(shipment_id: @order.shipment.id) }
      end

      assert @label.reload.requested?
      assert_match "PPN-295", @label.error
    end
  end
end
