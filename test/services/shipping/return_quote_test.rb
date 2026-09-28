require "test_helper"

module Shipping
  class ReturnQuoteTest < ActiveSupport::TestCase
    PRECO_URL = "#{Correios::Api::BASE_URL}/preco/v1/nacional".freeze

    setup do
      @prev_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      @shipment = orders(:delivered).shipment
    end

    teardown do
      Rails.cache = @prev_cache
    end

    test "quotes from the customer's CEP back to the store, at cost" do
      StoreSetting.current.update!(handling_fee_cents: 500)
      stub_return_quote

      prices = Shipping::ReturnQuote.call(@shipment)

      assert_equal({ sedex: 3270, pac: 2140, mini_envios: 1490 }, prices)
      assert_requested(:post, PRECO_URL) do |request|
        row = JSON.parse(request.body)["parametrosProduto"].first
        row["cepOrigem"] == @shipment.zip && row["cepDestino"] == Shipping::ORIGIN_CEP &&
          row["psObjeto"] == @shipment.weight_grams.to_s
      end
    end

    test "a service Correios will not carry quotes no price" do
      stub_request(:post, PRECO_URL).to_return(
        status: 200, headers: { "Content-Type" => "application/json" },
        body: [ { "coProduto" => "03220", "nuRequisicao" => "03220", "txErro" => "CEP de origem inválido" },
                { "coProduto" => "03298", "nuRequisicao" => "03298", "pcFinal" => "0,00" },
                { "coProduto" => "04960", "nuRequisicao" => "04227", "pcFinal" => "19,84" } ].to_json
      )

      assert_equal({ sedex: nil, pac: nil, mini_envios: nil }, Shipping::ReturnQuote.call(@shipment))
    end

    test "price_cents picks one service out of the quote" do
      stub_return_quote

      assert_equal 2140, Shipping::ReturnQuote.price_cents(@shipment, "pac")
    end

    test "caches per route and weight" do
      stub_return_quote

      2.times { Shipping::ReturnQuote.call(@shipment) }
      @shipment.weight_grams += 100
      Shipping::ReturnQuote.call(@shipment)

      assert_requested :post, PRECO_URL, times: 2
    end
  end
end
