require "test_helper"

class AccountOrdersFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @shipment = shipments(:delivered)
    @shipment.tracking_events.create!(position: 1, event_code: "PO", event_type: "01",
                                      description: "Postado em São Paulo / SP", occurred_at: 16.days.ago,
                                      payload: { "unidadeDestino" => { "tipo" => "Unidade de Tratamento",
                                                                       "endereco" => { "cidade" => "SAO PAULO", "uf" => "SP" } } })
    @shipment.tracking_events.create!(position: 2, event_code: "BDE", event_type: "01",
                                      description: "Objeto entregue ao destinatário", occurred_at: 11.days.ago)
  end

  test "signed-out users hitting /minha-conta/pedidos are sent to the sign-in page" do
    get account_orders_path
    assert_redirected_to new_user_session_path
  end

  test "index lists the customer's orders newest-first" do
    sign_in users(:confirmed)
    get account_orders_path
    assert_response :success
    body = response.body
    assert_match(/PG-202606140001/, body)
    assert_match(/PG-202605270004/, body)
    assert_match(/Aguardando pagamento/, body)
    assert_match(/Entregue/, body)
    assert_operator body.index("PG-202606140001"), :<, body.index("PG-202605270004")
  end

  test "index shows the empty state for a customer with no orders" do
    sign_in users(:orderless)
    get account_orders_path
    assert_response :success
    assert_match(/Você ainda não fez nenhum pedido/, response.body)
  end

  test "show on a delivered order renders items, the tracking timeline and a paid Pix line" do
    sign_in users(:confirmed)
    get account_order_path(orders(:delivered))
    assert_response :success
    body = response.body
    assert_match(/Entregue/, body)
    assert_match(/Seu pedido foi entregue/, body)
    assert_match(/Cor da carcaça: cristal/, body)
    assert_match(/Rastreamento/, body)
    assert_match(/Objeto entregue ao destinatário/, body)
    assert_match(%r{Postado em São Paulo / SP}, body)
    assert_match(/Destino: Unidade de Tratamento - SAO PAULO - SP/, body)
    refute_match(%r{PO/01}, body)
    assert_match(/Pago/, body)
    assert_match(/Pix/, body)
    assert_select ".order-detail__track-item.is-current .desc", text: /entregue ao destinatário/
  end

  test "show on an in-production order omits tracking and the cancel button" do
    sign_in users(:confirmed)
    get account_order_path(orders(:producing))
    assert_response :success
    body = response.body
    assert_match(/Em produção/, body)
    assert_no_match(/Rastreamento/, body)
    assert_no_match(/Cancelar pedido/, body)
    assert_match(/Cartão de crédito/, body)
  end

  test "show on an awaiting-payment order renders the cancel button and a pending payment line" do
    sign_in users(:confirmed)
    get account_order_path(orders(:awaiting))
    assert_response :success
    body = response.body
    assert_match(/Cancelar pedido/, body)
    assert_match(/Pagamento pendente/, body)
    assert_match(/Aguardando pagamento/, body)
  end

  test "show on an unknown number is 404" do
    sign_in users(:confirmed)
    get account_order_path("PG-999999999999")
    assert_response :not_found
  end

  test "cancelling an unpaid order moves it straight to cancelled" do
    sign_in users(:confirmed)
    order = orders(:awaiting)
    post cancelar_account_order_path(order)
    assert_redirected_to account_order_path(order)
    follow_redirect!
    assert_match(/Pedido cancelado/, response.body)
    assert order.reload.cancelled?
  end

  test "cancelling a paid order parks it in awaiting_refund for a manual refund" do
    sign_in users(:confirmed)
    order = orders(:confirmed_paid)
    post cancelar_account_order_path(order)
    assert_redirected_to account_order_path(order)
    follow_redirect!
    assert_match(/reembolso será processado manualmente/, response.body)
    assert order.reload.awaiting_refund?
  end

  test "cancelling an order past the window is rejected without changing state" do
    sign_in users(:confirmed)
    order = orders(:producing)
    post cancelar_account_order_path(order)
    assert_redirected_to account_order_path(order)
    follow_redirect!
    assert_match(/não pode mais ser cancelado/, response.body)
    assert order.reload.in_production?
  end

  test "a customer cannot see another customer's order" do
    sign_in users(:orderless)
    get account_order_path(orders(:awaiting))
    assert_response :not_found
  end
end
