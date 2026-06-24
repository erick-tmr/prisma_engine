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
      assert_select "form[action=?]", admin_order_transition_path(order, event: "to_production")
      assert_select ".act-btn.primary"
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

      post admin_order_transition_path(order, event: "to_production")
      assert_redirected_to admin_order_path(order)
      assert order.reload.in_production?

      change = order.status_changes.chronological.last
      assert_equal "in_production", change.to_status
      assert_equal users(:admin), change.actor

      follow_redirect!
      assert_select ".od-flash--ok"
    end

    test "an event not available for the current state is rejected" do
      sign_in users(:admin)
      order = orders(:confirmed_paid)

      post admin_order_transition_path(order, event: "issue_label")
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

    test "issue_label runs the Correios saga instead of a plain transition" do
      sign_in users(:admin)
      order = orders(:producing)

      assert_enqueued_with(job: Shipping::CreatePrePostagemJob, args: [ order.id ]) do
        post admin_order_transition_path(order, event: "issue_label")
      end
      assert_redirected_to admin_order_path(order)
      assert order.reload.in_production?
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
  end
end
