require "application_system_test_case"

class OrderHistoryTest < ApplicationSystemTestCase
  test "a customer sees their order history and opens one" do
    login_as_user(users(:confirmed))
    visit account_orders_path

    assert_selector ".orders__row", count: 4
    assert_selector ".status-pill", minimum: 1
    assert_text orders(:awaiting).number

    find(".orders__row", text: orders(:delivered).number).click

    assert_current_path account_order_path(orders(:delivered))
    assert_text orders(:delivered).number
  end

  test "an order detail page routes the customer to WhatsApp support, not a cancel button" do
    order = orders(:producing)
    login_as_user(users(:confirmed))
    visit account_order_path(order)

    assert_no_button "Cancelar pedido"
    assert_selector ".order-detail__support-text", text: "Precisa de ajuda sobre seu pedido?"
    assert_selector ".order-detail__support-btn[href='#{NavHelper.whatsapp_url("Olá tenho uma dúvida com relação ao pedido número #{order.number}")}']"
  end

  test "a customer with no orders sees the empty state" do
    login_as_user(users(:orderless))
    visit account_orders_path

    assert_selector ".empty-state"
    assert_no_selector ".orders__row"
  end
end
