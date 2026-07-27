require "test_helper"

module Shipping
  class QuoteTest < ActiveSupport::TestCase
    PRECO_URL = "#{Correios::Api::BASE_URL}/preco/v1/nacional".freeze
    PRAZO_URL = "#{Correios::Api::BASE_URL}/prazo/v1/nacional".freeze

    setup do
      @prev_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
    end

    teardown do
      Rails.cache = @prev_cache
    end

    test "returns eligible services with parsed cents + business days" do
      stub_preco(eligible: %w[03220 03298 04227])
      stub_prazo(eligible: %w[03220 03298 04227])

      services = Shipping::Quote.call(cep_destino: "01310100", weight_grams: 150)

      assert_equal %i[sedex pac mini_envios], services.map { |s| s[:key] }
      assert services.all? { |s| s[:eligible] }
      sedex = services.first
      assert_equal "SEDEX", sedex[:label]
      assert_equal 2284,    sedex[:price_cents]
      assert_equal "R$ 22,84", sedex[:price_formatted]
      assert_equal 2,       sedex[:business_days]
    end

    test "adds the configurable store handling fee on top of the Correios price" do
      StoreSetting.current.update!(handling_fee_cents: 500)
      stub_preco(eligible: %w[03220 03298 04227])
      stub_prazo(eligible: %w[03220 03298 04227])

      services = Shipping::Quote.call(cep_destino: "01310100", weight_grams: 150)

      sedex = services.first
      assert_equal 2484, sedex[:price_cents]
      assert_equal "R$ 24,84", sedex[:price_formatted]
    end

    test "Mini Envios coming back with a swapped coProduto is reported as ineligible with too_heavy" do
      stub_preco(eligible: %w[03220 03298], swapped: { "04227" => "04960" })
      stub_prazo(eligible: %w[03220 03298 04227])

      services = Shipping::Quote.call(cep_destino: "01310100", weight_grams: 350)

      mini = services.find { |s| s[:key] == :mini_envios }
      refute mini[:eligible]
      assert_equal :too_heavy, mini[:reason]
      assert_nil mini[:price_cents]
    end

    test "missing rows from either API are treated as ineligible" do
      stub_preco(eligible: %w[03220 03298 04227])
      stub_prazo(eligible: %w[03220 04227])

      services = Shipping::Quote.call(cep_destino: "01310100", weight_grams: 150)

      pac = services.find { |s| s[:key] == :pac }
      refute pac[:eligible]
      assert_equal :unavailable, pac[:reason]
    end

    test "caches the orchestrated response for 5 minutes per (cep, weight)" do
      stub_preco(eligible: %w[03220 03298 04227])
      stub_prazo(eligible: %w[03220 03298 04227])

      2.times { Shipping::Quote.call(cep_destino: "01310100", weight_grams: 150) }

      assert_requested :post, PRECO_URL, times: 1
      assert_requested :post, PRAZO_URL, times: 1
    end

    test "different (cep, weight) tuples each get their own cache entry" do
      stub_preco(eligible: %w[03220 03298 04227])
      stub_prazo(eligible: %w[03220 03298 04227])

      Shipping::Quote.call(cep_destino: "01310100", weight_grams: 150)
      Shipping::Quote.call(cep_destino: "20000000", weight_grams: 150)

      assert_requested :post, PRECO_URL, times: 2
    end

    test "propagates TransientError from Preco without caching" do
      stub_request(:post, PRECO_URL).to_return(status: 503, body: "down")

      assert_raises(Correios::Api::TransientError) do
        Shipping::Quote.call(cep_destino: "01310100", weight_grams: 150)
      end

      assert_raises(Correios::Api::TransientError) do
        Shipping::Quote.call(cep_destino: "01310100", weight_grams: 150)
      end
      assert_requested :post, PRECO_URL, times: 2
    end

    private

    def stub_preco(eligible:, swapped: {})
      body = []
      eligible.each_with_index do |code, i|
        body << { "coProduto" => code, "nuRequisicao" => code, "pcFinal" => "#{19 + i},84" }
      end
      swapped.each do |requested, returned|
        body << { "coProduto" => returned, "nuRequisicao" => requested, "pcFinal" => "18,08" }
      end
      stub_request(:post, PRECO_URL).to_return(
        status: 200, body: body.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    end

    def stub_prazo(eligible:)
      body = eligible.each_with_index.map do |code, i|
        { "coProduto" => code, "nuRequisicao" => code, "prazoEntrega" => 2 + i * 3 }
      end
      stub_request(:post, PRAZO_URL).to_return(
        status: 200, body: body.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    end
  end
end
