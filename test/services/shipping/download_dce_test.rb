require "test_helper"

module Shipping
  class DownloadDceTest < ActiveSupport::TestCase
    BASE = Correios::Api::BASE_URL
    URL = "#{BASE}/prepostagem/v1/prepostagens/dce/dace/impressao".freeze
    JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

    setup do
      @order = orders(:producing)
      @shipment = @order.shipment
      @shipment.update!(pre_post_id: "PR-77")
    end

    def stub_dace(body)
      stub_request(:post, URL).to_return(status: 200, body: body.to_json, headers: JSON_HEADERS)
    end

    test "names the file after the order and keeps the base64 verbatim" do
      stub_dace("objetos" => [ "PR-77" ], "dados" => "JVBERi0=")

      result = Shipping::DownloadDce.call(@shipment)

      assert_equal "declaracao-#{@order.number}.pdf", result.filename
      assert_equal "JVBERi0=", result.pdf_base64
    end

    test "refuses a document Correios answered for a different pré-postagem" do
      stub_dace("objetos" => [ "PR-somebody-else" ], "dados" => "JVBERi0=")

      error = assert_raises(Correios::Api::InvalidObjectError) { Shipping::DownloadDce.call(@shipment) }

      assert_match "PR-somebody-else", error.message
    end

    test "refuses a response that names no object at all" do
      stub_dace("dados" => "JVBERi0=")

      assert_raises(Correios::Api::InvalidObjectError) { Shipping::DownloadDce.call(@shipment) }
    end

    test "refuses a response carrying no document" do
      stub_dace("objetos" => [ "PR-77" ], "dados" => nil)

      assert_raises(Correios::Api::InvalidObjectError) { Shipping::DownloadDce.call(@shipment) }
    end
  end
end
