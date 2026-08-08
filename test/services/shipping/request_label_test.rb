require "test_helper"

module Shipping
  class RequestLabelTest < ActiveSupport::TestCase
    BASE = Correios::Api::BASE_URL
    URL = "#{BASE}/prepostagem/v1/prepostagens/rotulo/assincrono/pdf".freeze

    test "requests the label for the shipment and returns the idRecibo" do
      shipment = Shipment.create!(tracking_code: "AD1", pre_post_id: "PR-99", order: orders(:producing))
      stub_request(:post, URL)
        .with { |request| @sent = JSON.parse(request.body); true }
        .to_return(status: 200, body: { "idRecibo" => "R-77" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      recibo_id = Shipping::RequestLabel.call(shipment)

      assert_equal "R-77", recibo_id
      assert_equal [ "PR-99" ], @sent["idsPrePostagem"]
      assert_equal "0076738043", @sent["numeroCartaoPostagem"]
      assert_equal "P", @sent["tipoRotulo"]
      assert_equal "ET", @sent["formatoRotulo"]
    end

    test "a response with no usable idRecibo fails non-retryably instead of buying a blank recibo" do
      shipment = Shipment.create!(tracking_code: "AD1", pre_post_id: "PR-99", order: orders(:producing))

      [ {}, { "idRecibo" => nil }, { "idRecibo" => "" } ].each do |body|
        stub_request(:post, URL).to_return(status: 200, body: body.to_json,
                                           headers: { "Content-Type" => "application/json" })

        error = assert_raises(Correios::Api::InvalidObjectError) { Shipping::RequestLabel.call(shipment) }

        assert_match(/idRecibo came back empty/, error.message)
        assert_match(/PR-99/, error.message, "the operator needs the pré-postagem it belongs to")
        assert_not_kind_of Correios::Api::TransientError, error
      end
    end
  end
end
