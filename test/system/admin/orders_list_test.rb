require "application_system_test_case"

class AdminOrdersListTest < ApplicationSystemTestCase
  setup { login_as_user(users(:admin)) }

  test "an operator filters as they type and the url follows along" do
    order = orders(:confirmed_paid)
    visit admin_root_path

    assert_selector "tr[data-order]", minimum: 2

    fill_in "o-name", with: order.number

    # The url settles outside the swapped region, so wait on it before counting rows.
    assert_current_path(/q=#{order.number}/)
    assert_selector "#orders-count", text: "1 pedido"
    assert_selector "tr[data-order]", count: 1
  end

  test "a filtered url renders the same view when opened fresh" do
    order = orders(:confirmed_paid)

    visit "#{admin_root_path}?q=#{order.number}"

    assert_selector "tr[data-order]", count: 1
    assert_selector %(tr[data-order="#{order.number}"])
    assert_field "o-name", with: order.number
  end

  test "sorting is a link that carries the filter and flips on a second click" do
    visit admin_root_path

    find("th.sortable a[href*='sort=total']").click
    assert_current_path(/sort=total/)
    assert_selector "th.sorted a[href*='sort=total']"

    find("th.sortable a[href*='sort=total']").click
    assert_current_path(/dir=asc/)
  end

  test "back walks the operator through the states they filtered" do
    visit admin_root_path
    fill_in "o-name", with: orders(:confirmed_paid).number
    assert_current_path(/q=/)
    assert_selector "tr[data-order]", count: 1

    page.go_back
    assert_current_path admin_root_path, ignore_query: true
    assert_selector "tr[data-order]", minimum: 2
  end

  test "an operator filters the list down to the labels that expired" do
    expired = orders(:labeled)
    expired.shipment.expire_prepost(label: "Etiqueta expirada", at: 1.day.ago)
    expired.shipment.save!
    healthy = orders(:shipped_order)
    healthy.update_column(:status, "label_issued")

    visit admin_root_path
    assert_selector "tr[data-order]", minimum: 2

    find("#status-trigger").click
    find(%([data-st="label_expired"])).click

    assert_current_path(/status(%5B%5D|\[\])=label_expired/)
    assert_selector "#orders-count", text: "1 pedido"
    assert_selector %(tr[data-order="#{expired.number}"][data-label-expired="true"])
    assert_no_selector %(tr[data-order="#{healthy.number}"])
  end

  test "the expired filter names itself on the trigger and survives a fresh load" do
    expired = orders(:labeled)
    expired.shipment.expire_prepost(label: "Etiqueta expirada", at: 1.day.ago)
    expired.shipment.save!

    visit "#{admin_root_path}?status%5B%5D=label_expired"

    assert_selector "#status-trigger .val", text: "Etiqueta expirada"
    assert_selector %(tr[data-order="#{expired.number}"])

    find("#status-trigger").click
    assert_selector %([data-st="label_expired"].sel)
  end

  test "expired labels filtered out of the list can be batched into a new emission" do
    expired = orders(:labeled)
    expired.shipment.expire_prepost(label: "Etiqueta expirada", at: 1.day.ago)
    expired.shipment.save!

    visit "#{admin_root_path}?status%5B%5D=label_expired"
    assert_selector %(tr[data-order="#{expired.number}"])

    find(%([data-check="#{expired.number}"])).click

    assert_selector "#bulkbar", visible: true
    assert_selector "#bulk-n", text: "1"
    assert_selector %([data-act="issue_label"] .cnt), text: "1"
  end

  test "selecting rows drives the bulk bar" do
    visit admin_root_path

    first("[data-check]").click
    assert_selector "#bulkbar", visible: true
    assert_selector "#bulk-n", text: "1"

    find("#bulk-clear").click
    assert_no_selector "#bulkbar", visible: true
  end

  test "each list is its own page reached from the sidebar" do
    visit admin_root_path

    find(".sb-link", text: "Clientes").click
    assert_current_path admin_clients_path
    assert_selector "[data-list=clients] tr[data-client]", minimum: 1

    find(".sb-link", text: "Relatórios").click
    assert_current_path admin_reports_path
    assert_selector "[data-list=reports]"
  end

  test "the Correios column reports each stage of a label emission" do
    order = orders(:producing)
    label = order.shipment.create_shipping_label!(state: :pending)

    visit admin_root_path
    cell = "tr[data-order='#{order.number}'] [data-cor-state]"

    assert_selector "#{cell}[data-cor-state='queued']"
    assert_selector "tr[data-order='#{order.number}'].is-busy"

    label.update!(state: :requesting)
    assert_selector "#{cell}[data-cor-state='running']", wait: 8
    assert_selector "#{cell} .proc-run"

    label.record_error!("PPN-320 destinatário inválido")
    assert_selector "#{cell}[data-cor-state='failed']", wait: 8
    assert_selector "#{cell} .proc-retry"
    assert_no_selector "tr[data-order='#{order.number}'].is-busy"
  end

  test "a settled order shows its tracking code and never starts a poll" do
    order = orders(:labeled)
    order.shipment.update!(tracking_code: "PG515656027BR")

    visit admin_root_path

    assert_selector "tr[data-order='#{order.number}'] [data-cor-state='done'] .proc-ok .proc-code",
                    text: "PG515656027BR"
    assert_no_selector "tr[data-order='#{order.number}'] [data-cor-state='done'] .proc-sub"
    assert_selector "[data-part='procbar']", visible: :hidden
  end

  test "retrying a rejected label hands the order back to the saga" do
    order = orders(:producing)
    label = order.shipment.create_shipping_label!(state: :prepost_confirmed)
    label.record_error!("PPN-320 destinatário inválido")

    visit admin_root_path
    within "tr[data-order='#{order.number}']" do
      find(".proc-retry").click
    end

    assert_selector "tr[data-order='#{order.number}'] [data-cor-state='running']", wait: 8
    assert_nil label.reload.errored_at
  end

  test "the status pill settles with the Correios cell instead of going stale" do
    order = orders(:producing)
    label = order.shipment.create_shipping_label!(state: :requested)

    visit admin_root_path
    row = "tr[data-order='#{order.number}']"
    assert_selector "#{row} .pill", text: I18n.t("account.orders.states.in_production.label")

    ready_label!(label, filename: "etiqueta.pdf", pdf: Base64.strict_encode64("%PDF-1.4"))
    order.advance_to_label_issued!

    assert_selector "#{row} [data-cor-state='done']", wait: 8
    assert_selector "#{row} .pill", text: I18n.t("account.orders.states.label_issued.label")
    assert_selector "#{row}[data-status='label_issued']"
  end

  test "a busy row cannot be selected into a bulk action" do
    order = orders(:producing)
    order.shipment.create_shipping_label!(state: :requesting)

    visit admin_root_path
    find("#o-checkall").click

    assert_no_selector "tr[data-order='#{order.number}'] [data-check].on"
  end
end
