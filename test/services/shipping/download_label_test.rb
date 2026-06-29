require "test_helper"

module Shipping
  class DownloadLabelTest < ActiveSupport::TestCase
    BASE = Correios::Api::BASE_URL
    RECIBO = "R-55".freeze
    URL = "#{BASE}/prepostagem/v1/prepostagens/rotulo/download/assincrono/#{RECIBO}".freeze

    test "downloads the label and returns its filename and base64 PDF" do
      stub_request(:get, URL).to_return(
        status: 200, body: { "nome" => "etiqueta.pdf", "dados" => "JVBERi0=" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      result = Shipping::DownloadLabel.call(RECIBO)

      assert_equal "etiqueta.pdf", result.filename
      assert_equal "JVBERi0=", result.pdf_base64
    end
  end
end
