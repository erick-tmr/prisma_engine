require "application_system_test_case"

class AdminOrderDetailTest < ApplicationSystemTestCase
  test "an operator opens an order from the list and advances its status" do
    order = orders(:confirmed_paid)
    login_as_user(users(:admin))

    visit admin_root_path
    # Click a non-link cell to prove the whole row opens the order, not just the number.
    within "tr[data-order='#{order.number}']" do
      find(".who").click
    end

    assert_current_path admin_order_path(order)
    assert_selector ".od-head-num h1", text: order.number
    assert_selector ".pill.pill-lg", text: I18n.t("account.orders.states.payment_confirmed.label")

    find(".act-btn", text: I18n.t("admin.dashboard.bulk_actions.to_components")).click

    assert_selector ".od-flash--ok"
    assert_selector ".pill.pill-lg", text: I18n.t("account.orders.states.awaiting_components.label")
    assert order.reload.awaiting_components?
  end
end
