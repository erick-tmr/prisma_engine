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

    test "a label with no bytes is rejected rather than stored as a ready but empty PDF" do
      [ { "nome" => "etiqueta.pdf", "dados" => nil }, { "nome" => nil, "dados" => "JVBERi0=" },
        { "nome" => "etiqueta.pdf" } ].each do |body|
        Correios::Api::RotuloDownload.stub(:fetch, body) do
          error = assert_raises(Correios::Api::InvalidObjectError) { Shipping::DownloadLabel.call(RECIBO) }

          assert_match(/came back empty/, error.message)
          assert_match(/#{RECIBO}/, error.message)
        end
      end
    end
  end
end
