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

  test "the status card reports a label emission and settles it in place" do
    order = orders(:producing)
    label = order.shipment.create_shipping_label!(state: :requesting)
    login_as_user(users(:admin))

    visit admin_order_path(order)

    assert_selector ".headpill-proc", text: I18n.t("admin.orders.detail.label.chip_running")
    assert_selector ".act-proc .ap-head", text: I18n.t("admin.orders.detail.label.running_title")
    assert_selector ".lc-step.pending .lc-doing", text: I18n.t("admin.orders.lifecycle.doing_running")
    assert_selector ".act-btn[disabled]"

    ready_label!(label, filename: "etiqueta.pdf", pdf: Base64.strict_encode64("%PDF-1.4"))
    order.advance_to_label_issued!

    assert_selector ".pill.pill-lg", text: I18n.t("account.orders.states.label_issued.label"), wait: 8
    assert_no_selector ".act-proc"
    assert_no_selector ".headpill-proc"
    assert_selector ".act-btn", text: I18n.t("admin.orders.detail.print_label")
    assert_selector ".hist-item.is-latest .desc", text: I18n.t("account.orders.states.label_issued.label")
  end

  test "a rejected label offers a retry that clears the failure" do
    order = orders(:producing)
    label = order.shipment.create_shipping_label!(state: :prepost_confirmed)
    label.record_error!("PPN-320 destinatário inválido")
    login_as_user(users(:admin))

    visit admin_order_path(order)

    assert_selector ".headpill-proc.is-err"
    assert_selector ".act-proc.is-err .ap-sub", text: /PPN-320/
    find(".ap-retry").click

    assert_selector ".act-proc:not(.is-err) .ap-head", wait: 8
    assert_nil label.reload.errored_at
  end

  test "an operator makes the customer pay the return freight, quoted live" do
    stub_return_quote
    order = orders(:delivered)
    login_as_user(users(:admin))

    visit admin_order_path(order)

    assert_no_selector ".quote"
    assert_selector ".payer-cta-store", text: I18n.t("admin.orders.detail.start_return")
    find(".payer-opt", text: I18n.t("admin.orders.detail.return_freight.customer")).click

    assert_selector "[data-return-quote-price]", text: "R$ 14,90"
    select "SEDEX", from: "service"
    assert_selector "[data-return-quote-price]", text: "R$ 32,70"
    fill_in "reason", with: "Cartucho não salva o progresso."
    find(".payer-cta-customer", text: I18n.t("admin.orders.detail.return_freight.start_customer")).click

    assert_selector ".fc-state.wait", text: I18n.t("admin.orders.detail.return_freight.states.pending")
    assert_selector ".fc-row .v.big", text: "R$ 32,70"
    assert_selector ".label-wait"
    assert_selector ".lc-step.wait .lc-wait", text: I18n.t("admin.orders.lifecycle.wait_freight")
    assert_equal 3270, order.reload.return_shipment.freight_charge.amount_cents
  end
end
