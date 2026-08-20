require "test_helper"

module Admin
  class ClientsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    test "signed-out visitors are sent to the backoffice login" do
      get admin_client_path(users(:buyer))
      assert_redirected_to admin_login_path
    end

    test "signed-in non-admins are sent to the backoffice login" do
      sign_in users(:confirmed)
      get admin_client_path(users(:buyer))
      assert_redirected_to admin_login_path
    end

    test "the detail page carries the shared backoffice shell and the client identity" do
      sign_in users(:admin)
      client = users(:buyer)
      get admin_client_path(client)

      assert_response :success
      assert_select ".app[data-list=client]"
      assert_select ".sb-link.active[href=?]", admin_clients_path
      assert_select ".cl-head-name h1", text: client.full_name
      assert_select ".cust-row .v", text: client.email
      assert_select ".od-back[href=?]", admin_clients_path
    end

    test "the phone row opens the client WhatsApp chat in a new tab" do
      sign_in users(:admin)
      get admin_client_path(users(:buyer))

      assert_select ".cust-row a.cust-wa[href=?][target=?][rel=?]",
                    "https://web.whatsapp.com/send?phone=5511991112222", "_blank", "noopener"
    end

    test "a landline gets no WhatsApp button, since no account can answer it" do
      sign_in users(:admin)
      users(:buyer).update_column(:phone, "1133334444")
      get admin_client_path(users(:buyer))

      assert_select ".cust-row .v", text: "(11) 3333-4444"
      assert_select "a.cust-wa", false
    end

    test "an admin account is not reachable as a client" do
      sign_in users(:admin)
      get admin_client_path(users(:admin))

      assert_response :not_found
    end

    test "the situation tag mirrors the list view" do
      sign_in users(:admin)

      get admin_client_path(users(:locked))
      assert_select ".cl-head-name .tag.tag-locked"

      get admin_client_path(users(:unconfirmed))
      assert_select ".cl-head-name .tag.tag-pending"
      # The pending fixture has no phone: the card must dash it, not render a bare icon.
      assert_select ".cust-row .v", text: "–"

      get admin_client_path(users(:buyer))
      assert_select ".cl-head-name .tag.tag-active"
    end

    test "spend figures count only paid orders, never carts, cancellations or merges" do
      sign_in users(:admin)
      client = users(:orderless)
      client.orders.create!(subtotal_cents: 10_000, total_cents: 10_000, status: "delivered")
      client.orders.create!(subtotal_cents: 30_000, total_cents: 30_000, status: "awaiting_payment")
      client.orders.create!(subtotal_cents: 50_000, total_cents: 50_000, status: "cancelled")
      client.orders.create!(subtotal_cents: 70_000, total_cents: 70_000).update_column(:status, "merged")

      get admin_client_path(client)

      helpers = Admin::ClientsController.helpers
      assert_select ".cl-stats .cl-stat:nth-child(1) .v", text: "4"
      assert_select ".cl-stats .cl-stat:nth-child(2) .v", text: helpers.format_brl(10_000)
      assert_select ".cl-stats .cl-stat:nth-child(3) .v", text: helpers.format_brl(10_000)
    end

    test "a client with no orders shows dashes instead of a ticket and a last order" do
      sign_in users(:admin)
      get admin_client_path(users(:orderless))

      assert_select "#client-orders-empty.show"
      assert_select "#client-orders-table[hidden]"
      assert_select ".cl-stats .cl-stat:nth-child(3) .v", text: "–"
      assert_select ".cl-stats .cl-stat:nth-child(4) .v", text: "–"
    end

    test "every order row links to its detail page" do
      sign_in users(:admin)
      order = orders(:confirmed_paid)
      get admin_client_path(order.user)

      assert_select "tr[data-order=?] a.cell-link[href=?]", order.number, admin_order_path(order)
    end

    test "the order history pages through the query string, eight at a time" do
      sign_in users(:admin)
      client = users(:orderless)
      9.times { client.orders.create!(subtotal_cents: 1_000, total_cents: 1_000) }

      get admin_client_path(client)
      assert_select "#client-orders-body tr", count: 8
      assert_select ".tbl-foot .foot-range", text: /1–8 de 9 pedidos/
      assert_select ".tbl-foot a.pg[href=?]", "#{admin_client_path(client)}?page=2"

      get admin_client_path(client), params: { page: 2 }
      assert_select "#client-orders-body tr", count: 1
      assert_select ".tbl-foot a.pg.on", text: "2"
    end

    test "a fetch request returns just the order table, without the page shell" do
      sign_in users(:admin)
      get admin_client_path(users(:buyer)), headers: { "X-Requested-With" => "fetch" }

      assert_response :success
      assert_no_match(/<html/, response.body)
      assert_select "[data-part=count]", count: 1
      assert_select "[data-part=table]", count: 1
      assert_select ".sidebar", count: 0
    end

    test "a client who never spammed reads as clear, with the ladder untouched" do
      sign_in users(:admin)
      get admin_client_path(users(:orderless))

      assert_select ".sk-panel.sk-panel-clear"
      assert_select ".qb.qb-clear"
      assert_select ".sk-count b", text: "0"
      assert_select ".sk-rung.next .t", text: "1ª ocorrência"
      assert_select ".sk-empty"
      assert_select ".sk-item", count: 0
    end

    test "a client serving a ban shows the live countdown and the offending question" do
      sign_in users(:admin)
      client = users(:buyer)
      get admin_client_path(client)

      assert_select ".sk-panel.sk-panel-banned"
      assert_select ".qb.qb-banned"
      assert_select ".sk-count b", text: "1"
      assert_select "[data-strike-clock][data-expires-at]"
      assert_select "[data-strike-bar]"
      assert_select ".sk-rung.spent.current .t", text: "1ª ocorrência"
      assert_select ".sk-item .sk-q", text: /#{questions(:spam_yellow).body}/
    end

    test "a client whose penalty ran out reads as served, with the next one spelled out" do
      sign_in users(:admin)
      client = client_with_strikes(1, name: "Cliente Reincidente", cpf: SPARE_CPFS[0],
                                   last_strike_at: 30.days.ago)
      get admin_client_path(client)

      assert_select ".sk-panel.sk-panel-served"
      assert_select ".qb.qb-served"
      assert_select "[data-strike-clock]", count: 0
      assert_select ".sk-rung.next .t", text: "2ª ocorrência"
      assert_select ".sk-note", text: /1 mês sem perguntar/
    end

    test "a third strike reads as permanent, with every rung spent" do
      sign_in users(:admin)
      client = client_with_strikes(3, name: "Cliente Banido", cpf: SPARE_CPFS[1])
      get admin_client_path(client)

      assert_select ".sk-panel.sk-panel-perma"
      assert_select ".qb.qb-perma"
      assert_select ".sk-count b", text: "3"
      assert_select ".sk-rung.spent", count: 3
      assert_select ".sk-rung.next", count: 0
      assert_select ".sk-item", count: 3
      assert_select "[data-strike-clock]", count: 0
    end

    test "strikes past the permanent threshold keep the ladder at three rungs" do
      sign_in users(:admin)
      client = client_with_strikes(5, name: "Cliente Excesso", cpf: SPARE_CPFS[0])
      get admin_client_path(client)

      assert_response :success
      assert_select ".sk-panel.sk-panel-perma"
      assert_select ".sk-rung", count: 3
      assert_select ".sk-rung.spent.current", count: 1
      assert_select ".sk-item", count: 5
      assert_select ".sk-item:last-child .pen", text: /3ª ocorrência/
    end

    test "each strike offers the inbox link and the removal button" do
      sign_in users(:admin)
      strike = question_strikes(:spam_yellow_buyer)
      get admin_client_path(users(:buyer))

      assert_select ".sk-item[data-strike=?]", strike.id.to_s do
        assert_select "a.sk-btn[href=?]", admin_questions_path(pergunta: strike.question_id)
        assert_select "form[data-confirm][action=?]", admin_client_strike_path(users(:buyer), strike)
      end
    end

    test "the address book lists the default first and flags it" do
      sign_in users(:admin)
      get admin_client_path(addresses(:locked_home).user)

      assert_select ".addr-list .addr:first-child .addr-tag.main"
      assert_select ".addr-body .cep", text: /CEP/
    end

    test "the address book names who receives the delivery" do
      sign_in users(:admin)
      address = addresses(:locked_home)
      get admin_client_path(address.user)

      assert_select ".addr-receiver strong", text: address.receiver_name
      assert_select ".addr-receiver .doc", text: "CPF 745.201.839-79"
    end

    test "a client with no address says so" do
      sign_in users(:admin)
      get admin_client_path(users(:orderless))

      assert_select ".addr-list .addr-body", text: /ainda não cadastrou/
    end
  end
end
