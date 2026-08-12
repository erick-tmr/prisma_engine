require "test_helper"

class CheckoutTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  PRECO_URL = "#{Correios::Api::BASE_URL}/preco/v1/nacional".freeze
  PRAZO_URL = "#{Correios::Api::BASE_URL}/prazo/v1/nacional".freeze
  LINKS_URL = "#{InfinitePay::Api::BASE_URL}/links".freeze
  CHECKOUT_URL = "https://checkout.infinitepay.io/prisma_games?lenc=abc".freeze

  setup do
    Rails.cache.clear
    @user = users(:confirmed)
    @address = @user.addresses.create!(
      zip: "01310100", street: "Av. Paulista", number: "1578",
      neighborhood: "Bela Vista", city: "São Paulo", state: "SP",
      receiver_name: "Cliente Confirmado", receiver_cpf: "52998224725"
    )
  end

  teardown do
    Rails.cache.clear
  end

  test "GET /checkout requires login" do
    get checkout_path
    assert_redirected_to new_user_session_path
  end

  test "GET /checkout with an empty cart redirects to the cart" do
    sign_in @user
    get checkout_path
    assert_redirected_to cart_path
  end

  test "GET /checkout renders the delivery screen with the real cart + saved address" do
    sign_in @user
    add_yellow_to_cart
    get checkout_path

    assert_response :success
    assert_match(/Entrega e pagamento/, response.body)
    assert_match(/Cliente Confirmado/, response.body)
    assert_match(/Pokemon Yellow Version/, response.body)
    assert_select ".checkout__sum-item-name a[href=?]", product_path(products(:yellow))
    assert_select "a.checkout__sum-thumb[href=?]", product_path(products(:yellow))
    assert_select "form#checkout-form[action=?]", checkout_create_path
    assert_select "input[name=address_id][value=?]", @address.id.to_s
  end

  test "GET /checkout renders the made-to-order request block in the summary" do
    sign_in @user
    post cart_items_path, params: {
      product_id: products(:pedido_game).id, quantity: 1,
      request: { game: "Pokemon Unbound", notes: "carcaça translúcida roxa" }
    }
    post cart_items_path, params: {
      product_id: products(:pedido_no_image).id, quantity: 1, request: { game: "Zelda Redux" }
    }
    get checkout_path

    assert_response :success
    assert_select ".checkout__sum-thumb img"
    assert_select ".checkout__sum-thumb--pedido i.bi-card-checklist"
    assert_select ".checkout__sum-item-pedido-row .v", text: "Pokemon Unbound"
    assert_select ".checkout__sum-item-pedido-row .v", text: "carcaça translúcida roxa"
    assert_select ".checkout__sum-item-pedido-row .v.is-empty", text: "Sem observações"
  end

  test "GET /checkout uses the minimal checkout chrome, not the storefront header" do
    sign_in @user
    add_yellow_to_cart
    get checkout_path
    assert_match(/Compra 100% segura/, response.body)
    assert_match(/Etapas do checkout/, response.body)
    assert_no_match(/data-toggle="drawer"/, response.body)
  end

  test "GET /checkout pre-selects the shipping service chosen on the cart" do
    sign_in @user
    add_yellow_to_cart
    post cart_finalize_path, params: { shipping_service: "pac" }
    get checkout_path
    assert_response :success
    assert_match(/data-preselected="pac"/, response.body)
  end

  test "GET /checkout drops a now-unpublished line and still renders the rest" do
    sign_in @user
    add_yellow_to_cart
    post cart_items_path, params: { product_id: products(:metroid).id, quantity: 1, option_ids: [] }
    products(:metroid).update!(published: false)

    get checkout_path
    assert_response :success
    assert_no_match(/Metroid/, response.body)
    assert_match(/Pokemon Yellow Version/, response.body)
  end

  test "POST /checkout creates the order, clears the cart, and redirects to InfinitePay" do
    sign_in @user
    add_yellow_to_cart
    stub_preco_prazo
    stub_links

    assert_difference "Order.count", 1 do
      post checkout_create_path, params: { address_id: @address.id, shipping_service: "pac" }
    end

    order = Order.last
    assert_equal CHECKOUT_URL, response.headers["Location"]
    assert_equal "pac", order.shipment.service
    assert_requested(:post, LINKS_URL) do |req|
      body = JSON.parse(req.body)
      assert_equal order.number, body["order_nsu"]
      assert_equal payments_webhook_url(order.webhook_token), body["webhook_url"]
      true
    end

    post cart_quote_path, params: { cep: "01310-100" }, as: :json
    assert_response :unprocessable_entity
  end

  test "GET /checkout shows the merge offer when the customer has open paid orders" do
    sign_in @user
    add_yellow_to_cart
    get checkout_path

    assert_response :success
    assert_select "section.checkout__merge[data-merge]"
    assert_select "input[name=merge_everything]"
    assert_select ".checkout__merge-order", 1
    assert_select ".checkout__merge-thumbs"
    assert_select ".checkout__merge .status-pill"
  end

  test "GET /checkout hides the merge offer when there is nothing to merge" do
    sign_in users(:buyer)
    post cart_items_path, params: { product_id: products(:yellow).id, quantity: 1, option_ids: [] }
    get checkout_path

    assert_response :success
    assert_select "section.checkout__merge", false
  end

  test "POST /checkout with merge_everything creates a carrier + merge plan and redirects to payment" do
    sign_in @user
    add_yellow_to_cart
    stub_preco_prazo
    stub_links

    assert_difference [ "Order.count", "OrderMerge.count" ], 1 do
      post checkout_create_path, params: { merge_everything: "1" }
    end

    carrier = Order.last
    assert carrier.order_merge.present?
    assert_equal orders(:confirmed_paid), carrier.order_merge.master_order
    assert_equal CHECKOUT_URL, response.headers["Location"]
  end

  test "POST /checkout with merge_everything sends no frete item when the master already covers it" do
    sign_in @user
    add_yellow_to_cart
    orders(:confirmed_paid).shipment.update!(shipping_cents: 99_999)
    stub_preco_prazo
    stub_links

    assert_difference [ "Order.count", "OrderMerge.count" ], 1 do
      post checkout_create_path, params: { merge_everything: "1" }
    end

    carrier = Order.last
    assert_equal 0, carrier.shipment.shipping_cents
    assert_equal carrier.subtotal_cents, carrier.total_cents
    assert_requested(:post, LINKS_URL) do |req|
      items = JSON.parse(req.body)["items"]
      assert_empty items.select { |item| item["price"].zero? }
      assert_equal carrier.total_cents, items.sum { |item| item["price"] * item["quantity"] }
      true
    end
  end

  test "POST /checkout with merge_everything leaves no carrier or plan behind when the link fails" do
    sign_in @user
    add_yellow_to_cart
    stub_preco_prazo
    stub_request(:post, LINKS_URL).to_return(status: 503, body: "down")

    assert_no_difference [ "Order.count", "OrderMerge.count", "OrderItem.count", "Shipment.count" ] do
      post checkout_create_path, params: { merge_everything: "1" }
    end
    assert_redirected_to checkout_path
    assert_match(/não foi possível iniciar o pagamento/i, flash[:alert])
  end

  test "POST /checkout with merge_everything but no eligible orders flashes the merge error" do
    sign_in users(:buyer)
    post cart_items_path, params: { product_id: products(:yellow).id, quantity: 1, option_ids: [] }

    post checkout_create_path, params: { merge_everything: "1" }
    assert_redirected_to checkout_path
    assert_match(/não tem outros pedidos/i, flash[:alert])
  end

  test "POST /checkout stores the customer observation on the order" do
    sign_in @user
    add_yellow_to_cart
    stub_preco_prazo
    stub_links

    post checkout_create_path, params: { address_id: @address.id, shipping_service: "pac", observation: "Deixar na portaria" }
    assert_equal "Deixar na portaria", Order.last.observation
  end

  test "POST /checkout stores the Correios note on the shipment" do
    sign_in @user
    add_yellow_to_cart
    stub_preco_prazo
    stub_links

    post checkout_create_path, params: { address_id: @address.id, shipping_service: "pac", receiver_obs: "Entregar na portaria" }
    assert_equal "Entregar na portaria", Order.last.shipment.receiver_obs
  end

  test "POST /checkout as JSON returns the payment + return URLs for the new-tab flow" do
    sign_in @user
    add_yellow_to_cart
    stub_preco_prazo
    stub_links

    assert_difference "Order.count", 1 do
      post checkout_create_path, params: { address_id: @address.id, shipping_service: "pac" }, as: :json
    end

    order = Order.last
    assert_response :success
    assert_equal CHECKOUT_URL, response.parsed_body["payment_url"]
    assert_equal checkout_return_url(order_nsu: order.number), response.parsed_body["return_url"]

    post cart_quote_path, params: { cep: "01310-100" }, as: :json
    assert_response :unprocessable_entity
  end

  test "POST /checkout as JSON returns a 422 with the message when the link fails" do
    sign_in @user
    add_yellow_to_cart
    stub_preco_prazo
    stub_request(:post, LINKS_URL).to_return(status: 503, body: "down")

    assert_no_difference "Order.count" do
      post checkout_create_path, params: { address_id: @address.id, shipping_service: "pac" }, as: :json
    end
    assert_response :unprocessable_entity
    assert_match(/não foi possível iniciar o pagamento/i, response.parsed_body["error"])
  end

  test "POST /checkout leaves no order behind when the InfinitePay link fails" do
    sign_in @user
    add_yellow_to_cart
    stub_preco_prazo
    stub_request(:post, LINKS_URL).to_return(status: 503, body: "down")

    assert_no_difference [ "Order.count", "OrderItem.count", "Shipment.count", "OrderStatusChange.count" ] do
      post checkout_create_path, params: { address_id: @address.id, shipping_service: "pac" }
    end
    assert_redirected_to checkout_path
    assert_match(/não foi possível iniciar o pagamento/i, flash[:alert])
    assert cookies[:cart].present?
  end

  test "POST /checkout with an empty cart flashes the empty-cart error" do
    sign_in @user
    assert_no_difference "Order.count" do
      post checkout_create_path, params: { address_id: @address.id, shipping_service: "pac" }
    end
    assert_redirected_to checkout_path
    assert_equal "Seu carrinho está vazio.", flash[:alert]
  end

  test "POST /checkout rejects an address that is not the buyer's" do
    other = User.create!(
      email: "outro@example.com", password: "password123",
      full_name: "Outro Cliente", cpf: "39053344705", phone: "11900000000", confirmed_at: 1.day.ago
    )
    foreign = other.addresses.create!(
      zip: "04534003", street: "Rua X", number: "1", neighborhood: "Itaim",
      city: "São Paulo", state: "SP", receiver_name: "Outro", receiver_cpf: "39053344705"
    )
    sign_in @user
    add_yellow_to_cart

    assert_no_difference "Order.count" do
      post checkout_create_path, params: { address_id: foreign.id, shipping_service: "pac" }
    end
    assert_equal "Selecione um endereço de entrega válido.", flash[:alert]
  end

  test "POST /checkout flashes when the chosen service is unavailable" do
    sign_in @user
    add_yellow_to_cart
    stub_preco_prazo

    assert_no_difference "Order.count" do
      post checkout_create_path, params: { address_id: @address.id, shipping_service: "carrier_pigeon" }
    end
    assert_match(/não está disponível/, flash[:alert])
  end

  test "POST /checkout/endereco saves a new address and returns to checkout pre-selecting it" do
    sign_in @user
    add_yellow_to_cart

    assert_difference -> { @user.addresses.count }, 1 do
      post checkout_address_path, params: { address: {
        zip: "37500100", street: "Rua das Acácias", number: "45", complement: "Casa",
        neighborhood: "Centro", city: "Itajubá", state: "MG",
        receiver_name: "Maria Pereira", receiver_cpf: "39053344705"
      } }
    end
    assert_redirected_to checkout_path

    follow_redirect!
    new_address = @user.addresses.order(:created_at).last
    assert_select "input[name=address_id][value=?][checked]", new_address.id.to_s
  end

  test "POST /checkout/endereco re-shows the checkout with the error on invalid input" do
    sign_in @user
    add_yellow_to_cart

    assert_no_difference -> { @user.addresses.count } do
      post checkout_address_path, params: { address: {
        zip: "37500100", street: "Rua X", number: "45", neighborhood: "Centro",
        city: "Itajubá", state: "MG", receiver_name: "Maria", receiver_cpf: "11111111111"
      } }
    end
    assert_redirected_to checkout_path
    assert flash[:alert].present?
  end

  private

  def add_yellow_to_cart
    post cart_items_path, params: { product_id: products(:yellow).id, quantity: 1, option_ids: [] }
  end

  def stub_links
    stub_request(:post, LINKS_URL).to_return(
      status: 200, body: { "url" => CHECKOUT_URL }.to_json, headers: { "Content-Type" => "application/json" }
    )
  end

  def stub_preco_prazo
    stub_request(:post, PRECO_URL).to_return(
      status: 200,
      body: [
        { "coProduto" => "03220", "nuRequisicao" => "03220", "pcFinal" => "19,84" },
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
