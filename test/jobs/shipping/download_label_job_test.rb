require "test_helper"

module Shipping
  class DownloadLabelJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    BASE = Correios::Api::BASE_URL
    RECIBO = "R-42".freeze
    URL = "#{BASE}/prepostagem/v1/prepostagens/rotulo/download/assincrono/#{RECIBO}".freeze

    setup do
      @prev_token = ENV["CORREIOS_CARTAO_API_TOKEN"]
      ENV["CORREIOS_CARTAO_API_TOKEN"] = "test-token"
      @order = orders(:producing)
      @label = @order.create_shipping_label!(state: :requested, recibo_id: RECIBO)
    end

    teardown do
      ENV["CORREIOS_CARTAO_API_TOKEN"] = @prev_token
    end

    test "downloads the PDF, marks the label ready and moves the order to label_issued" do
      stub_request(:get, URL).to_return(
        status: 200,
        body: { "nome" => "etiqueta.pdf", "dados" => Base64.strict_encode64("%PDF-1.4") }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      Shipping::DownloadLabelJob.perform_now(@order.id)

      assert @label.reload.ready?
      assert_equal "etiqueta.pdf", @label.filename
      assert_equal "%PDF-1.4", @label.pdf_bytes
      assert @order.reload.label_issued?
    end
  end
end
