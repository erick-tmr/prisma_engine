require "test_helper"

module Admin
  class OrdersControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers
    include ActiveJob::TestHelper

    test "non-admins are sent to the backoffice login" do
      get admin_order_path(orders(:producing))
      assert_redirected_to admin_login_path
    end

    test "an unknown order number is a 404" do
      sign_in users(:admin)
      get admin_order_path("PG-000000000000")
      assert_response :not_found
    end

    test "show renders the detail and a primary action for an order with manual moves" do
      sign_in users(:admin)
      order = orders(:confirmed_paid)
      get admin_order_path(order)

      assert_response :success
      assert_select ".od-head-num h1", text: order.number
      assert_select "form[action=?]", admin_order_transition_path(order, event: "to_components")
      assert_select ".act-btn.primary"
    end

    test "show renders the customer observation panel when the order has one" do
      sign_in users(:admin)
      order = orders(:confirmed_paid)
      order.update!(observation: "Cliente pediu embalagem extra")
      get admin_order_path(order)

      assert_response :success
      assert_select ".od-meta-head", text: /Observação do cliente/
      assert_select ".od-obs-text", text: /Cliente pediu embalagem extra/
    end

    test "show renders the made-to-order request panel per line with a blank-notes fallback" do
      sign_in users(:admin)
      order = orders(:confirmed_paid)
      order.order_items.create!(
        name: "Custom Order Game", unit_price_cents: 19_000, quantity: 1,
        product: products(:pedido_game), requested_game: "Pokemon Unbound", request_notes: "v2.1, carcaça roxa"
      )
      order.order_items.create!(
        name: "Custom Order Game", unit_price_cents: 19_000, quantity: 1,
        product: products(:pedido_game), requested_game: "Zelda Redux"
      )
      get admin_order_path(order)

      assert_response :success
      assert_select ".od-item-pedido", count: 2
      assert_select ".od-pedido-field .v", text: "Pokemon Unbound"
      assert_select ".od-pedido-field .v", text: "v2.1, carcaça roxa"
      assert_select ".od-pedido-field .v.is-empty", text: "Sem observações"
    end

    test "show renders the danger cancel action with a confirm prompt for an unpaid order" do
      sign_in users(:admin)
      get admin_order_path(orders(:awaiting))

      assert_response :success
      assert_select "form[data-confirm] .act-btn.danger"
    end

    test "show renders the Correios timeline for a shipped order" do
      sign_in users(:admin)
      shipment = orders(:shipped_order).shipment
      shipment.tracking_events.create!(
        position: 3, event_code: "PO", event_type: "01", description: "Objeto postado", occurred_at: 7.days.ago,
        payload: { "unidade" => { "tipo" => "Agência dos Correios",
                                  "endereco" => { "cidade" => "CAMBUI", "uf" => "MG" } } }
      )
      shipment.tracking_events.create!(
        position: 4, event_code: "RO", event_type: "01", description: "Objeto em trânsito", occurred_at: 5.days.ago,
        payload: { "unidadeDestino" => { "tipo" => "Unidade de Tratamento",
                                         "endereco" => { "cidade" => "SAO PAULO", "uf" => "SP" } } }
      )
      get admin_order_path(orders(:shipped_order))

      assert_response :success
      assert_select ".od-track-item", minimum: 2
      assert_select ".od-track-item.is-current"
      assert_select ".od-track .meta", text: "Agência dos Correios - CAMBUI - MG"
      assert_select ".od-track .meta", text: "Destino: Unidade de Tratamento - SAO PAULO - SP"
    end

    test "show renders the printable label and the auto-next note for a label_issued order" do
      sign_in users(:admin)
      order = orders(:labeled)
      get admin_order_path(order)

      assert_response :success
      assert_select "a[href=?]", admin_order_label_path(order)
      assert_select ".act-none"
    end

    test "show renders the status history newest-first" do
      sign_in users(:admin)
      get admin_order_path(orders(:delivered))

      assert_response :success
      assert_select ".hist-item.is-latest"
      assert_select ".hist-item", minimum: 2
    end

    test "show renders a lifecycle branch step for a non-linear state" do
      sign_in users(:admin)
      order = orders(:producing)
      order.transition_to!("production_issue")
      get admin_order_path(order)

      assert_response :success
      assert_select ".lc-step.branch.current"
    end

    test "a manual transition advances the order, records the operator and flashes" do
      sign_in users(:admin)
      order = orders(:confirmed_paid)

      post admin_order_transition_path(order, event: "to_components")
      assert_redirected_to admin_order_path(order)
      assert order.reload.awaiting_components?

      change = order.status_changes.chronological.last
      assert_equal "awaiting_components", change.to_status
      assert_equal users(:admin), change.actor

      follow_redirect!
      assert_select ".od-flash--ok"
    end

    test "show renders the delivery problem branch and resolution actions" do
      sign_in users(:admin)
      order = orders(:shipped_order)
      order.transition_to!("delivery_issue")

      get admin_order_path(order)
      assert_response :success
      assert_select ".lc-step.branch.current"
      assert_select "form[data-confirm] .act-btn.danger"
    end

    test "an operator can re-ship a delivery_issue order" do
      sign_in users(:admin)
      order = orders(:shipped_order)
      order.transition_to!("delivery_issue")

      post admin_order_transition_path(order, event: "reship")
      assert_redirected_to admin_order_path(order)
      assert order.reload.shipped?

      change = order.status_changes.chronological.last
      assert_equal "shipped", change.to_status
      assert_equal users(:admin), change.actor

      follow_redirect!
      assert_select ".od-flash--ok"
    end

    test "an action not available for the current state is rejected" do
      sign_in users(:admin)
      order = orders(:confirmed_paid)

      post admin_order_transition_path(order, event: "flag_issue")
      assert_redirected_to admin_order_path(order)
      assert order.reload.payment_confirmed?

      follow_redirect!
      assert_select ".od-flash--alert"
    end

    test "an unknown event is rejected without changing state" do
      sign_in users(:admin)
      order = orders(:producing)

      post admin_order_transition_path(order, event: "nope")
      assert_redirected_to admin_order_path(order)
      assert order.reload.in_production?
    end

    test "the detail screen no longer offers a manual issue_label action" do
      sign_in users(:admin)
      order = orders(:producing)
      get admin_order_path(order)

      assert_response :success
      assert_select "form[action=?]", admin_order_transition_path(order, event: "flag_issue")
      assert_select "form[action=?]", admin_order_transition_path(order, event: "issue_label"), count: 0
    end

    test "the label endpoint streams the stored Correios PDF" do
      sign_in users(:admin)
      get admin_order_label_path(orders(:labeled))

      assert_response :success
      assert_equal "application/pdf", response.media_type
      assert_match(/\A%PDF/, response.body)
    end

    test "the label endpoint 404s when no ready label exists" do
      sign_in users(:admin)
      get admin_order_label_path(orders(:producing))

      assert_response :not_found
    end

    test "the order detail renders the shared backoffice nav, including the reports tab" do
      sign_in users(:admin)
      get admin_order_path(orders(:producing))

      assert_response :success
      assert_select "aside.sidebar a.sb-link[data-view=?]", "reports"
      assert_select "aside.sidebar a.sb-link[href=?]", admin_reports_path
    end
  end
end
