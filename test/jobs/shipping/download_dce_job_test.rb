require "test_helper"

module Shipping
  class DownloadDceJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    BASE = Correios::Api::BASE_URL
    URL = "#{BASE}/prepostagem/v1/prepostagens/dce/dace/impressao".freeze
    JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

    setup do
      @order = orders(:producing)
      @shipment = @order.shipment
      @shipment.update!(pre_post_id: "PR-77")
      @label = @shipment.create_shipping_label!(state: :label_downloaded, filename: "etiqueta.pdf", pdf_base64: "JVBERi0=")
    end

    def stub_dace(status: 200, body: nil)
      body ||= { "objetos" => [ "PR-77" ], "dados" => Base64.strict_encode64("%PDF-1.4 dace") }.to_json
      stub_request(:post, URL).to_return(status: status, body: body, headers: JSON_HEADERS)
    end

    test "stores the declaração and only now moves the order to label_issued" do
      stub_dace

      Shipping::DownloadDceJob.perform_now(shipment_id: @shipment.id)

      @label.reload
      assert @label.ready?
      assert_equal "declaracao-#{@order.number}.pdf", @label.dce_filename
      assert_equal "%PDF-1.4 dace", @label.dce_bytes
      assert_equal "JVBERi0=", @label.pdf_base64
      assert @order.reload.label_issued?
    end

    test "a return keeps its status, since the inbound leg announces nothing" do
      order = orders(:delivered)
      Shipping::StartReturn.call(order: order)
      inbound = order.reload.return_shipment
      inbound.update!(pre_post_id: "PR-88")
      inbound.shipping_label.store_label!(filename: "etiqueta.pdf", pdf: "JVBERi0=")
      stub_dace(body: { "objetos" => [ "PR-88" ], "dados" => Base64.strict_encode64("%PDF-1.4 dace") }.to_json)

      Shipping::DownloadDceJob.perform_now(shipment_id: inbound.id)

      assert inbound.shipping_label.reload.ready?
      assert order.reload.awaiting_return?
    end

    test "no-ops on a label that has not downloaded its etiqueta yet" do
      @label.update!(state: :requested)

      Shipping::DownloadDceJob.perform_now(shipment_id: @shipment.id)

      assert @label.reload.requested?
      assert_not_requested :post, URL
    end

    test "no-ops once the label is already ready" do
      @label.store_dce!(filename: "declaracao.pdf", pdf: "x")

      Shipping::DownloadDceJob.perform_now(shipment_id: @shipment.id)

      assert_not_requested :post, URL
    end

    test "a definitive refusal is recorded on the label and re-raised for an operator" do
      stub_dace(status: 404, body: { "msgs" => [ "PPN-376: sem chave DC-e." ] }.to_json)

      assert_raises(Correios::Api::Error) { Shipping::DownloadDceJob.perform_now(shipment_id: @shipment.id) }

      assert @label.reload.label_downloaded?, "the label parks where it was, short of ready"
      assert_match "PPN-376", @label.error
      assert @order.reload.in_production?
    end

    test "a transient failure is retried without touching the label" do
      stub_dace(status: 500, body: "boom")

      assert_enqueued_jobs 1, only: Shipping::DownloadDceJob do
        Shipping::DownloadDceJob.perform_now(shipment_id: @shipment.id)
      end

      assert @label.reload.label_downloaded?
      assert_nil @label.error
    end
  end
end
