require "test_helper"

module Shipping
  class ConfirmPrePostagemTest < ActiveSupport::TestCase
    BASE = Correios::Api::BASE_URL
    CODE = "AD601193771BR".freeze
    URL = "#{BASE}/prepostagem/v2/prepostagens?codigoObjeto=#{CODE}".freeze

    setup do
      @prev_token = ENV["CORREIOS_CARTAO_API_TOKEN"]
      ENV["CORREIOS_CARTAO_API_TOKEN"] = "test-token"
      @shipment = shipments(:awaiting)
      @shipment.update!(tracking_code: CODE)
    end

    teardown do
      ENV["CORREIOS_CARTAO_API_TOKEN"] = @prev_token
    end

    test "refreshes the status and returns the shipment once Pré-postado" do
      stub_status(item(2, "Pré-postado"))

      result = Shipping::ConfirmPrePostagem.call(@shipment)

      assert_equal @shipment, result
      @shipment.reload
      assert_equal 2, @shipment.correios_status
      assert_equal :prepostado, @shipment.correios_status_name
      assert_equal "Pré-postado", @shipment.correios_status_label
      assert_not_nil @shipment.correios_status_at
    end

    test "refreshes the status but raises PrePostagemPending while still Pendente" do
      stub_status(item(7, "Pendente"))

      assert_raises(Shipping::PrePostagemPending) { Shipping::ConfirmPrePostagem.call(@shipment) }

      assert_equal 7, @shipment.reload.correios_status
    end

    test "raises PrePostagemPending when the object is not visible in the query view yet" do
      stub_request(:get, URL).to_return(
        status: 200, body: { "itens" => [] }.to_json, headers: { "Content-Type" => "application/json" }
      )

      assert_raises(Shipping::PrePostagemPending) { Shipping::ConfirmPrePostagem.call(@shipment) }
      assert_nil @shipment.reload.correios_status
    end

    test "raises PrePostagemPending without calling Correios when there is no tracking code" do
      @shipment.update!(tracking_code: nil)

      assert_raises(Shipping::PrePostagemPending) { Shipping::ConfirmPrePostagem.call(@shipment) }
      assert_not_requested :get, %r{/prepostagem/v2/prepostagens}
    end

    private

    def stub_status(item)
      stub_request(:get, URL).to_return(
        status: 200, body: { "itens" => [ item ] }.to_json, headers: { "Content-Type" => "application/json" }
      )
    end

    def item(status, label)
      {
        "codigoObjeto" => CODE,
        "statusAtual" => status,
        "descStatusAtual" => label,
        "dataHoraStatusAtual" => "2026-06-22T20:00:34.711579"
      }
    end
  end
end
