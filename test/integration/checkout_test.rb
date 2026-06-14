require "test_helper"

class CheckoutTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  PRECO_URL = "#{Correios::Api::BASE_URL}/preco/v1/nacional".freeze
  PRAZO_URL = "#{Correios::Api::BASE_URL}/prazo/v1/nacional".freeze
  LINKS_URL = "#{InfinitePay::Api::BASE_URL}/links".freeze
  CHECKOUT_URL = "https://checkout.infinitepay.io/prisma_games?lenc=abc".freeze

  setup do
    Rails.cache.clear
    @prev_token = ENV["CORREIOS_API_TOKEN"]
    @prev_handle = ENV["INFINITEPAY_HANDLE"]
    ENV["CORREIOS_API_TOKEN"] = "test-api"
    ENV["INFINITEPAY_HANDLE"] = "prisma_games"
    @user = users(:confirmed)
    @address = @user.addresses.create!(
      zip: "01310100", street: "Av. Paulista", number: "1578",
      neighborhood: "Bela Vista", city: "São Paulo", state: "SP",
      receiver_name: "Cliente Confirmado", receiver_cpf: "52998224725"
    )
  end

  teardown do
    ENV["CORREIOS_API_TOKEN"] = @prev_token
    ENV["INFINITEPAY_HANDLE"] = @prev_handle
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
    assert_select "form#checkout-form[action=?]", checkout_create_path
    assert_select "input[name=address_id][value=?]", @address.id.to_s
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
    assert_equal "pac", order.shipping_service
    assert_requested(:post, LINKS_URL) do |req|
      body = JSON.parse(req.body)
      assert_equal order.number, body["order_nsu"]
      assert_equal payments_webhook_url(order.webhook_token), body["webhook_url"]
      true
    end
    # cart cleared → a follow-up quote sees an empty cart
    post cart_quote_path, params: { cep: "01310-100" }, as: :json
    assert_response :unprocessable_entity
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
    # cart cleared → a follow-up quote sees an empty cart
    post cart_quote_path, params: { cep: "01310-100" }, as: :json
    assert_response :unprocessable_entity
  end

  test "POST /checkout as JSON returns a 422 with the message when the link fails" do
    sign_in @user
    add_yellow_to_cart
    stub_preco_prazo
    stub_request(:post, LINKS_URL).to_return(status: 503, body: "down")

    post checkout_create_path, params: { address_id: @address.id, shipping_service: "pac" }, as: :json
    assert_response :unprocessable_entity
    assert_match(/não foi possível iniciar o pagamento/i, response.parsed_body["error"])
  end

  test "POST /checkout keeps the order but flashes when the InfinitePay link fails" do
    sign_in @user
    add_yellow_to_cart
    stub_preco_prazo
    stub_request(:post, LINKS_URL).to_return(status: 503, body: "down")

    assert_difference "Order.count", 1 do
      post checkout_create_path, params: { address_id: @address.id, shipping_service: "pac" }
    end
    assert_redirected_to checkout_path
    assert_match(/não foi possível iniciar o pagamento/i, flash[:alert])
  end

  test "GET /checkout/retorno records the transaction and shows the pending state" do
    sign_in @user
    order = create_order_for(@user)

    get checkout_return_path, params: {
      order_nsu: order.number, transaction_nsu: "txn-123",
      receipt_url: "https://recibo.infinitepay.io/txn-123", capture_method: "credit_card"
    }

    assert_response :success
    assert_match(/Pagamento em processamento/, response.body)        # awaiting webhook confirmation
    assert_select ".pay-return.state-pending"
    assert_select "[data-countdown][data-deadline]"                  # 24h cancel countdown
    order.reload
    assert_equal "txn-123", order.external_id
    assert_equal "https://recibo.infinitepay.io/txn-123", order.receipt_url
    assert_equal "credit_card", order.payment_method
  end

  test "GET /checkout/retorno shows the success state for a confirmed order" do
    sign_in @user
    order = create_order_for(@user)
    order.confirm_payment!

    get checkout_return_path, params: { order_nsu: order.number }

    assert_response :success
    assert_match(/Pagamento confirmado/, response.body)
    assert_select ".pay-return.state-success"
  end

  test "GET /checkout/retorno shows the failed state for a cancelled order" do
    sign_in @user
    order = create_order_for(@user)
    order.cancel!

    get checkout_return_path, params: { order_nsu: order.number }

    assert_response :success
    assert_match(/cancelado por falta de pagamento/i, response.body)
    assert_select ".pay-return.state-failed"
  end

  test "GET /checkout/retorno shows the failed state once an unpaid order passes the deadline" do
    sign_in @user
    order = create_order_for(@user)

    travel_to 25.hours.from_now do
      get checkout_return_path, params: { order_nsu: order.number }
    end

    assert_response :success
    assert_select ".pay-return.state-failed"
    assert order.reload.awaiting_payment?, "the page computes failed from the deadline; the job persists the cancel"
  end

  test "GET /checkout/retorno without a transaction just renders the order" do
    sign_in @user
    order = create_order_for(@user)

    get checkout_return_path, params: { order_nsu: order.number }

    assert_response :success
    assert_nil order.reload.external_id
  end

  test "GET /checkout/retorno shows aguardando with no payment method when none is known yet" do
    sign_in @user
    order = create_order_for(@user)
    assert_nil order.payment_method

    get checkout_return_path, params: { order_nsu: order.number }

    assert_response :success
    assert_select ".pay-return.state-pending .pay-status", text: /Aguardando/
    assert_select ".info-cell .strong", text: "Pix", count: 0
    assert_no_match(/Cartão de crédito/, response.body)
  end

  test "POST /checkout/retorno/pagar regenerates the link and redirects to InfinitePay" do
    sign_in @user
    order = create_order_for(@user)
    stub_links

    post checkout_pay_path, params: { order_nsu: order.number }

    assert_equal CHECKOUT_URL, response.headers["Location"]
    assert_requested(:post, LINKS_URL) do |req|
      body = JSON.parse(req.body)
      assert_equal order.number, body["order_nsu"]
      assert_equal payments_webhook_url(order.webhook_token), body["webhook_url"]
      true
    end
  end

  test "POST /checkout/retorno/pagar on an already-paid order returns to the status page" do
    sign_in @user
    order = create_order_for(@user)
    order.confirm_payment!

    post checkout_pay_path, params: { order_nsu: order.number }

    assert_redirected_to checkout_return_path(order_nsu: order.number)
    assert_not_requested(:post, LINKS_URL)
  end

  test "POST /checkout/retorno/pagar flashes when the link cannot be regenerated" do
    sign_in @user
    order = create_order_for(@user)
    stub_request(:post, LINKS_URL).to_return(status: 503, body: "down")

    post checkout_pay_path, params: { order_nsu: order.number }

    assert_redirected_to checkout_return_path(order_nsu: order.number)
    assert_match(/não foi possível iniciar o pagamento/i, flash[:alert])
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

  def create_order_for(user)
    order = Order.create!(
      user: user, subtotal_cents: 18_000, shipping_cents: 1_984, total_cents: 19_984,
      shipping_service: "pac",
      ship_receiver_name: "Cliente Confirmado", ship_receiver_cpf: "52998224725",
      ship_zip: "01310100", ship_street: "Av. Paulista", ship_number: "1578",
      ship_neighborhood: "Bela Vista", ship_city: "São Paulo", ship_state: "SP"
    )
    order.order_items.create!(name: "Cartucho", unit_price_cents: 18_000, quantity: 1, chosen_options: [ "ROM: Zelda" ])
    order
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
