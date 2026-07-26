require "test_helper"

class CartQuotesTest < ActionDispatch::IntegrationTest
  CEP_URL   = "#{Correios::Api::BASE_URL}/cep/v2/enderecos/01310100".freeze
  PRECO_URL = "#{Correios::Api::BASE_URL}/preco/v1/nacional".freeze
  PRAZO_URL = "#{Correios::Api::BASE_URL}/prazo/v1/nacional".freeze

  setup do
    Rails.cache.clear
    stub_cep
  end

  teardown do
    Rails.cache.clear
  end

  test "returns destination + eligible services for a populated cart" do
    add_yellow_to_cart
    stub_preco_prazo(all_eligible: true)

    post cart_quote_path, params: { cep: "01310-100" }, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal "01310-100", body["cep"]
    assert_equal "São Paulo", body["destination"]["city"]
    assert_equal "SP", body["destination"]["state"]

    keys = body["services"].map { |s| s["key"] }
    assert_equal %w[sedex pac mini_envios], keys
    assert body["services"].all? { |s| s["eligible"] }
    sedex = body["services"].first
    assert_equal 2284, sedex["price_cents"]
    assert_equal "R$ 22,84", sedex["price_formatted"]
    assert_equal 2, sedex["business_days"]
  end

  test "marks Mini Envios ineligible with the too_heavy message when Correios swaps the code" do
    add_yellow_to_cart
    stub_preco_prazo(all_eligible: false)

    post cart_quote_path, params: { cep: "01310-100" }, as: :json

    assert_response :success
    mini = response.parsed_body["services"].last
    assert_equal "mini_envios", mini["key"]
    refute mini["eligible"]
    assert_equal "too_heavy", mini["reason"]
    assert_match(/Mini Envios aceita pacotes de até 300g/, mini["message"])
  end

  test "package weight sent to Correios includes the GOTM brindes mass per line × qty plus the caixa+flyer overhead" do
    post cart_items_path, params: {
      product_id: products(:yellow).id, quantity: 2,
      option_ids: [ product_options(:yellow_caixa_com).id ]
    }
    stub_preco_prazo(all_eligible: true)

    post cart_quote_path, params: { cep: "01310-100" }, as: :json

    assert_requested(:post, PRECO_URL) do |req|
      body = JSON.parse(req.body)
      body["parametrosProduto"].all? { |p| p["psObjeto"] == "202" }
    end
  end

  test "rejects requests with a malformed CEP" do
    add_yellow_to_cart

    post cart_quote_path, params: { cep: "123" }, as: :json

    assert_response :unprocessable_entity
    assert_equal "CEP inválido.", response.parsed_body["error"]
  end

  test "rejects requests with an empty cart" do
    post cart_quote_path, params: { cep: "01310-100" }, as: :json

    assert_response :unprocessable_entity
    assert_equal "Seu carrinho está vazio.", response.parsed_body["error"]
  end

  test "returns 422 when Correios reports the CEP doesn't exist" do
    add_yellow_to_cart
    stub_request(:get, CEP_URL).to_return(status: 404, body: '{"message":"nao encontrado"}')

    post cart_quote_path, params: { cep: "01310-100" }, as: :json

    assert_response :unprocessable_entity
    assert_equal "CEP inválido.", response.parsed_body["error"]
  end

  test "returns 503 when Correios is unavailable" do
    add_yellow_to_cart
    stub_request(:post, PRECO_URL).to_return(status: 503, body: "down")
    stub_request(:post, PRAZO_URL).to_return(status: 200, body: "[]")

    post cart_quote_path, params: { cep: "01310-100" }, as: :json

    assert_response :service_unavailable
    assert_match(/Correios indisponível/, response.parsed_body["error"])
  end

  test "falls back to zero brindes weight when no GOTM is set for the current month" do
    GameOfTheMonth.destroy_all
    post cart_items_path, params: {
      product_id: products(:yellow).id, quantity: 1,
      option_ids: [ product_options(:yellow_caixa_com).id ]
    }
    stub_preco_prazo(all_eligible: true)

    post cart_quote_path, params: { cep: "01310-100" }, as: :json

    assert_response :success
    assert_requested(:post, PRECO_URL) do |req|
      JSON.parse(req.body)["parametrosProduto"].all? { |p| p["psObjeto"] == "112" }
    end
  end

  test "auth failures surface as 503 with the unexpected-error message" do
    add_yellow_to_cart
    stub_request(:post, PRECO_URL).to_return(status: 401, body: "unauthorized")
    stub_request(:post, PRAZO_URL).to_return(status: 200, body: "[]")

    post cart_quote_path, params: { cep: "01310-100" }, as: :json

    assert_response :service_unavailable
    assert_match(/Erro inesperado/, response.parsed_body["error"])
  end

  test "every service returning a CEP txErro produces a 422 CEP inválido response" do
    add_yellow_to_cart
    stub_request(:post, PRECO_URL).to_return(status: 200, body: [
      { "coProduto" => "03220", "nuRequisicao" => "03220",
        "txErro"    => "ERP-005: CEP inexistente (00000000). --> UF DESTINO" },
      { "coProduto" => "03298", "nuRequisicao" => "03298",
        "txErro"    => "ERP-005: CEP inexistente." },
      { "coProduto" => "04227", "nuRequisicao" => "04227",
        "txErro"    => "ERP-005: CEP inexistente." }
    ].to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:post, PRAZO_URL).to_return(status: 200, body: "[]")

    post cart_quote_path, params: { cep: "01310-100" }, as: :json

    assert_response :unprocessable_entity
    assert_equal "CEP inválido.", response.parsed_body["error"]
  end

  test "a mix of CEP and non-CEP txErro with no eligible services returns the unexpected-error message" do
    add_yellow_to_cart
    stub_request(:post, PRECO_URL).to_return(status: 200, body: [
      { "coProduto" => "03220", "nuRequisicao" => "03220",
        "txErro"    => "ERP-005: CEP inexistente." },
      { "coProduto" => "03298", "nuRequisicao" => "03298",
        "txErro"    => "ERR-XX: serviço indisponível na origem." },
      { "coProduto" => "04227", "nuRequisicao" => "04227",
        "txErro"    => "ERR-YY: regra de coleta." }
    ].to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:post, PRAZO_URL).to_return(status: 200, body: "[]")

    post cart_quote_path, params: { cep: "01310-100" }, as: :json

    assert_response :service_unavailable
    assert_match(/Erro inesperado/, response.parsed_body["error"])
  end

  test "a single-service CEP txErro alongside eligible services renders 200 with that row marked ineligible" do
    add_yellow_to_cart
    stub_request(:post, PRECO_URL).to_return(status: 200, body: [
      { "coProduto" => "03220", "nuRequisicao" => "03220",
        "txErro"    => "ERP-005: CEP inexistente." },
      { "coProduto" => "03298", "nuRequisicao" => "03298", "pcFinal" => "20,84" },
      { "coProduto" => "04227", "nuRequisicao" => "04227", "pcFinal" => "11,15" }
    ].to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:post, PRAZO_URL).to_return(status: 200, body: [
      { "coProduto" => "03220", "nuRequisicao" => "03220", "prazoEntrega" => 2 },
      { "coProduto" => "03298", "nuRequisicao" => "03298", "prazoEntrega" => 7 },
      { "coProduto" => "04227", "nuRequisicao" => "04227", "prazoEntrega" => 9 }
    ].to_json, headers: { "Content-Type" => "application/json" })

    post cart_quote_path, params: { cep: "01310-100" }, as: :json

    assert_response :success
    sedex = response.parsed_body["services"].first
    refute sedex["eligible"]
    assert_equal "invalid_cep", sedex["reason"]
    assert_equal "CEP não atendido por este serviço.", sedex["message"]
  end

  test "a successful quote is remembered and restored on the cart page within the TTL" do
    add_yellow_to_cart
    stub_preco_prazo(all_eligible: true)
    post cart_quote_path, params: { cep: "01310-100" }, as: :json
    assert_response :success

    get cart_path
    assert_response :success
    assert_match(/data-initial-quote=/, response.body)
    assert_match(/value="01310-100"/, response.body)
  end

  test "a quote older than the 30-minute TTL is not restored" do
    add_yellow_to_cart
    stub_preco_prazo(all_eligible: true)
    post cart_quote_path, params: { cep: "01310-100" }, as: :json

    travel_to 31.minutes.from_now do
      get cart_path
      assert_response :success
      assert_no_match(/data-initial-quote=/, response.body)
    end
  end

  test "a stale-weight quote keeps the CEP + chosen service and re-quotes instead of resetting" do
    add_yellow_to_cart
    stub_preco_prazo(all_eligible: true)
    post cart_quote_path, params: { cep: "01310-100" }, as: :json
    line_id = Cart::Bag.from_cookie(JSON.parse(request.cookie_jar.signed[:cart].to_json)).items.first["id"]

    patch cart_item_path(line_id), params: { quantity: 2, shipping_service: "sedex" }
    get cart_path
    assert_response :success
    assert_no_match(/data-initial-quote=/, response.body)
    assert_match(/data-recalc-cep="01310-100"/, response.body)
    assert_match(/data-recalc-service="sedex"/, response.body)
    assert_match(/value="01310-100"/, response.body)
  end

  private

  def add_yellow_to_cart
    post cart_items_path, params: { product_id: products(:yellow).id, quantity: 1, option_ids: [] }
  end

  def stub_cep
    stub_request(:get, CEP_URL).to_return(
      status:  200,
      body:    { "cep" => "01310100", "uf" => "SP", "logradouro" => "Av. Paulista",
                 "bairro" => "Bela Vista", "nomeMunicipio" => "São Paulo" }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  def stub_preco_prazo(all_eligible:)
    preco_body = [
      { "coProduto" => "03220", "nuRequisicao" => "03220", "pcFinal" => "19,84" },
      { "coProduto" => "03298", "nuRequisicao" => "03298", "pcFinal" => "20,84" }
    ]
    if all_eligible
      preco_body << { "coProduto" => "04227", "nuRequisicao" => "04227", "pcFinal" => "11,15" }
    else
      preco_body << { "coProduto" => "04960", "nuRequisicao" => "04227", "pcFinal" => "18,08" }
    end

    stub_request(:post, PRECO_URL).to_return(
      status: 200, body: preco_body.to_json,
      headers: { "Content-Type" => "application/json" }
    )
    stub_request(:post, PRAZO_URL).to_return(
      status: 200,
      body: [
        { "coProduto" => "03220", "nuRequisicao" => "03220", "prazoEntrega" => 2 },
        { "coProduto" => "03298", "nuRequisicao" => "03298", "prazoEntrega" => 7 },
        { "coProduto" => "04227", "nuRequisicao" => "04227", "prazoEntrega" => 9 }
      ].to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end
end
