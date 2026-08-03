require "application_system_test_case"

class AdminClientDetailTest < ApplicationSystemTestCase
  test "an operator opens a client from the list, pages the orders and opens one" do
    client = users(:confirmed)
    order = orders(:confirmed_paid)
    # Backdated so the four fixture orders keep the first page and the filler spills onto the second.
    9.times { |i| client.orders.create!(subtotal_cents: 1_000, total_cents: 1_000, created_at: (100 + i).days.ago) }
    login_as_user(users(:admin))

    visit admin_clients_path
    # Click a non-link cell to prove the whole row opens the client, not just the name.
    within "tr[data-client='#{client.id}']" do
      find(".em").click
    end

    assert_current_path admin_client_path(client)
    assert_selector ".cl-head-name h1", text: client.full_name
    assert_selector "#client-orders-body tr", count: 8

    find(".tbl-foot a.pg", text: "2", exact_text: true).click

    assert_current_path(/page=2/)
    assert_selector ".tbl-foot a.pg.on", text: "2"
    assert_selector "#client-orders-body tr", count: 5

    find(".tbl-foot a.pg", text: "1", exact_text: true).click

    assert_no_current_path(/page=2/)
    # Click a non-link cell to prove the whole row opens the order, not just the number.
    within "tr[data-order='#{order.number}']" do
      find("td.cell-num", match: :first).click
    end

    assert_current_path admin_order_path(order)
    assert_selector ".od-head-num h1", text: order.number
  end

  test "an operator removes a strike and the question goes back to the inbox" do
    client = users(:buyer)
    strike = question_strikes(:spam_yellow_buyer)
    login_as_user(users(:admin))

    visit admin_client_path(client)

    assert_selector ".sk-panel.sk-panel-banned"
    assert_selector ".qb.qb-banned"
    # The countdown is painted by JS from data-expires-at, so a rendered day proves it ran.
    assert_selector "[data-strike-clock] [data-clock-value='days']", text: /\d\d/
    assert_selector "[data-strike-bar]"

    accept_confirm { find(".sk-item[data-strike='#{strike.id}'] .sk-btn.undo").click }

    assert_selector ".od-flash--ok"
    assert_selector ".sk-panel.sk-panel-clear"
    assert_selector ".sk-empty"
    assert_equal "awaiting_answer", strike.question.reload.status
    assert_empty client.question_strikes.reload
  end
end
