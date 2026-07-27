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
end
