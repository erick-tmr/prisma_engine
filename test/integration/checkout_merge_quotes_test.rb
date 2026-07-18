require "test_helper"

class CheckoutMergeQuotesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  PRECO_URL = "#{Correios::Api::BASE_URL}/preco/v1/nacional".freeze
  PRAZO_URL = "#{Correios::Api::BASE_URL}/prazo/v1/nacional".freeze

  setup { Rails.cache.clear }
  teardown { Rails.cache.clear }

  test "requires login" do
    post checkout_merge_quote_path, as: :json
    assert_response :unauthorized
  end

  test "returns the consolidation preview for an eligible customer" do
    sign_in users(:confirmed)
    add_yellow_to_cart
    stub_preco_prazo

    post checkout_merge_quote_path, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal orders(:confirmed_paid).number, body["master_number"]
    assert_equal "pac", body["service"]
    assert_equal 2384, body["combined_cents"]
    assert_equal 2990, body["paid_fretes_cents"]
    assert_equal 0, body["delta_cents"]
    assert_equal 1, body["order_count"]
  end

  test "422 with a friendly message when the customer has nothing to merge" do
    sign_in users(:buyer)
    add_yellow_to_cart

    post checkout_merge_quote_path, as: :json

    assert_response :unprocessable_entity
    assert_match(/não tem outros pedidos/i, response.parsed_body["error"])
  end

  test "422 when Correios is unavailable" do
    sign_in users(:confirmed)
    add_yellow_to_cart
    stub_request(:post, PRECO_URL).to_return(status: 503, body: "down")
    stub_request(:post, PRAZO_URL).to_return(status: 200, body: "[]")

    post checkout_merge_quote_path, as: :json

    assert_response :unprocessable_entity
    assert_match(/frete/i, response.parsed_body["error"])
  end

  private

  def add_yellow_to_cart
    post cart_items_path, params: { product_id: products(:yellow).id, quantity: 1, option_ids: [] }
  end

  def stub_preco_prazo
    stub_request(:post, PRECO_URL).to_return(
      status: 200,
      body: [
        { "coProduto" => "03220", "nuRequisicao" => "03220", "pcFinal" => "24,84" },
        { "coProduto" => "03298", "nuRequisicao" => "03298", "pcFinal" => "20,84" },
        { "coProduto" => "04227", "nuRequisicao" => "04227", "pcFinal" => "11,15" }
      ].to_json,
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
