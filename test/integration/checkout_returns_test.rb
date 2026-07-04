require "test_helper"

class CheckoutReturnsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  LINKS_URL = "#{InfinitePay::Api::BASE_URL}/links".freeze
  CHECKOUT_URL = "https://checkout.infinitepay.io/prisma_games?lenc=abc".freeze

  setup do
    @user = users(:confirmed)
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
    assert_select ".pay-return.pay-return--pending"
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
    assert_select ".pay-return.pay-return--success"
  end

  test "GET /checkout/retorno shows the failed state for a cancelled order" do
    sign_in @user
    order = create_order_for(@user)
    order.cancel!

    get checkout_return_path, params: { order_nsu: order.number }

    assert_response :success
    assert_match(/cancelado por falta de pagamento/i, response.body)
    assert_select ".pay-return.pay-return--failed"
  end

  test "GET /checkout/retorno shows the failed state once an unpaid order passes the deadline" do
    sign_in @user
    order = create_order_for(@user)

    travel_to 25.hours.from_now do
      get checkout_return_path, params: { order_nsu: order.number }
    end

    assert_response :success
    assert_select ".pay-return.pay-return--failed"
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
    assert_select ".pay-return.pay-return--pending .pay-return__pay-status", text: /Aguardando/
    assert_select ".pay-return__info-cell .strong", text: "Pix", count: 0
    assert_no_match(/Cartão de crédito/, response.body)
  end

  test "GET /checkout/retorno echoes the customer's observation when present" do
    sign_in @user
    order = create_order_for(@user)
    order.update!(observation: "Entregar após as 18h")

    get checkout_return_path, params: { order_nsu: order.number }

    assert_response :success
    assert_select ".pay-return__note-text", text: /Entregar após as 18h/
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

  def stub_links
    stub_request(:post, LINKS_URL).to_return(
      status: 200, body: { "url" => CHECKOUT_URL }.to_json, headers: { "Content-Type" => "application/json" }
    )
  end

  def create_order_for(user)
    order = Order.create!(user: user, subtotal_cents: 18_000, total_cents: 19_984)
    order.create_shipment!(
      service: "pac", shipping_cents: 1_984, weight_grams: 120, height_cm: 4, width_cm: 16, length_cm: 24,
      receiver_name: "Cliente Confirmado", receiver_cpf: "52998224725",
      zip: "01310100", street: "Av. Paulista", number: "1578",
      neighborhood: "Bela Vista", city: "São Paulo", state: "SP"
    )
    order.order_items.create!(name: "Cartucho", unit_price_cents: 18_000, quantity: 1, chosen_options: [ "ROM: Zelda" ])
    order
  end
end
