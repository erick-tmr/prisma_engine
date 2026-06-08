require "test_helper"

class AccountOrdersFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "signed-out users hitting /minha-conta/pedidos are sent to the sign-in page" do
    get account_orders_path
    assert_redirected_to new_user_session_path
  end

  test "index lists the 5 mocked orders with status badges" do
    sign_in users(:confirmed)
    get account_orders_path
    assert_response :success
    assert_match(/PG-2026-000001/, response.body)
    assert_match(/PG-2026-000005/, response.body)
    assert_match(/Aguardando pagamento/, response.body)
    assert_match(/Entregue/, response.body)
  end

  test "show on a delivered order renders the full timeline and items" do
    sign_in users(:confirmed)
    get account_order_path("PG-2026-000005")
    assert_response :success
    assert_match(/Entregue/, response.body)
    assert_match(/Seu pedido foi entregue/, response.body)
    assert_match(/Rastreamento/, response.body)
    assert_match(/BDE\/01/, response.body)
    assert_match(/Pix/, response.body)
  end

  test "show on a shipped order renders the partial tracking timeline" do
    sign_in users(:confirmed)
    get account_order_path("PG-2026-000004")
    assert_response :success
    assert_match(/Rastreamento/, response.body)
    assert_match(/PO\/01/, response.body)
  end

  test "show on an em_producao order omits the tracking section" do
    sign_in users(:confirmed)
    get account_order_path("PG-2026-000003")
    assert_response :success
    assert_match(/Em produção/, response.body)
    assert_no_match(/Rastreamento/, response.body)
    # No cancel button — past the cancellation window.
    assert_no_match(/Cancelar pedido/, response.body)
    # InfinitePay label for non-Pix mock.
    assert_match(/InfinitePay/, response.body)
  end

  test "show on aguardando_pagamento renders the presentational cancel button" do
    sign_in users(:confirmed)
    get account_order_path("PG-2026-000001")
    assert_response :success
    assert_match(/Cancelar pedido/, response.body)
  end

  test "show on an unknown number is 404" do
    sign_in users(:confirmed)
    get account_order_path("PG-9999-999999")
    assert_response :not_found
  end
end
