require "test_helper"

module Admin
  class OrderPresenterTest < ActiveSupport::TestCase
    PATHS = {
      "awaiting_payment"    => [],
      "payment_confirmed"   => %w[payment_confirmed],
      "awaiting_components" => %w[payment_confirmed awaiting_components],
      "in_production"       => %w[payment_confirmed in_production],
      "production_issue"    => %w[payment_confirmed in_production production_issue],
      "label_issued"        => %w[payment_confirmed in_production label_issued],
      "shipped"             => %w[payment_confirmed in_production label_issued shipped],
      "delivered"           => %w[payment_confirmed in_production label_issued shipped delivered],
      "delivery_issue"      => %w[payment_confirmed in_production label_issued shipped delivery_issue],
      "awaiting_refund"     => %w[payment_confirmed awaiting_refund],
      "cancelled"           => %w[cancelled],
      "merged"              => %w[payment_confirmed merged]
    }.freeze

    def order_in(status, service: "pac")
      order = Order.create!(user: users(:confirmed), subtotal_cents: 32_000, total_cents: 34_990)
      Shipment.create!(
        order: order, service: service, shipping_cents: 2_990,
        receiver_name: "Cliente Confirmado", receiver_cpf: "52998224725", zip: "01310100",
        street: "Rua das Flores", number: "150", neighborhood: "Centro", city: "São Paulo", state: "SP"
      )
      PATHS.fetch(status).each { |step| order.transition_to!(step) }
      OrderPresenter.new(order.reload)
    end

    test "delegates raw order data" do
      presenter = order_in("payment_confirmed")
      assert_match(/\APG-/, presenter.number)
      assert_equal "payment_confirmed", presenter.status
      assert_equal "Pagamento confirmado", presenter.status_label
      assert_equal 2_990, presenter.shipping_cents
      assert_equal "PAC", presenter.shipping_service_label
    end

    test "shipping_service_label maps the Correios service code" do
      assert_equal "SEDEX", order_in("payment_confirmed", service: "sedex").shipping_service_label
    end

    test "status_description is the admin-facing copy" do
      assert_equal I18n.t("admin.orders.states.in_production.description"),
                   order_in("in_production").status_description
    end

    test "receiver_obs reads the shipment note, or nil without a note or shipment" do
      presenter = order_in("payment_confirmed")
      assert_nil presenter.receiver_obs

      presenter.order.shipment.update!(receiver_obs: "Entregar na portaria")
      assert_equal "Entregar na portaria", OrderPresenter.new(presenter.order.reload).receiver_obs

      presenter.order.shipment.destroy!
      assert_nil OrderPresenter.new(presenter.order.reload).receiver_obs
    end

    test "a merged order renders its lifecycle and description without breaking" do
      presenter = order_in("merged")
      assert_equal "Consolidado", presenter.status_label
      assert_equal I18n.t("admin.orders.states.merged.description"), presenter.status_description
      assert_empty presenter.available_actions
      branch = presenter.lifecycle.find { |step| step.classes.include?("branch") }
      assert_equal "Consolidado", branch.label
    end

    test "a merged order exposes its master pointer even after its shipment is destroyed" do
      presenter = order_in("merged")
      master = orders(:confirmed_paid)
      presenter.order.shipment.destroy!
      presenter.order.update!(merged_into: master)

      fresh = OrderPresenter.new(presenter.order.reload)
      assert_predicate fresh, :merged?
      assert_equal master, fresh.merged_into
    end

    test "available_actions for payment_confirmed: a single primary move, no confirm (production is report-only)" do
      actions = order_in("payment_confirmed").available_actions
      assert_equal %w[to_components], actions.map { |a| a[:id] }
      assert_equal "act-btn primary", actions.first[:button_class]
      assert_equal({}, actions.first[:form_data])
      assert_equal "Aguardando componentes", actions.first[:target_label]
    end

    test "available_actions for awaiting_payment: a danger cancel carrying a confirm prompt" do
      action = order_in("awaiting_payment").available_actions.sole
      assert_equal "cancel", action[:id]
      assert_equal "act-btn danger", action[:button_class]
      assert_includes action[:form_data][:confirm], "Cancelar o pedido"
    end

    test "available_actions for in_production offers only flag_issue, not a manual issue_label" do
      actions = order_in("in_production").available_actions
      assert_equal %w[flag_issue], actions.map { |a| a[:id] }
    end

    test "available_actions is empty for terminal/automatic states" do
      %w[label_issued shipped delivered cancelled].each do |status|
        assert_empty order_in(status).available_actions, status
      end
    end

    test "auto_next_note is present only for automatic-next states" do
      assert_equal I18n.t("admin.orders.auto_next.delivered"), order_in("delivered").auto_next_note
      assert_nil order_in("in_production").auto_next_note
    end

    test "label_printable? only for a label_issued order with a ready stored label" do
      assert OrderPresenter.new(orders(:labeled)).label_printable?
      assert_not order_in("in_production").label_printable?
      assert_not order_in("label_issued").label_printable?
      assert_not OrderPresenter.new(orders(:shipped_order)).label_printable?
    end

    test "lifecycle on the happy path marks done/current/upcoming without a branch" do
      steps = order_in("in_production").lifecycle
      assert_equal 6, steps.size
      assert_equal %w[done done current upcoming upcoming upcoming], steps.map(&:classes)
      assert_equal I18n.t("admin.orders.lifecycle.auto_webhook"), steps.second.auto_note
      assert_nil steps.first.auto_note
    end

    test "lifecycle inserts a branch step for a non-linear state" do
      steps = order_in("production_issue").lifecycle
      branch = steps.find { |step| step.classes == "branch current" }
      assert_not_nil branch
      assert_equal "Problema na produção", branch.label
    end

    test "available_actions for delivery_issue offers returned, refund, reship and a danger cancel" do
      actions = order_in("delivery_issue").available_actions
      assert_equal %w[mark_returned issue_refund reship cancel_issue], actions.map { |a| a[:id] }
      cancel = actions.find { |a| a[:id] == "cancel_issue" }
      assert_equal "act-btn danger", cancel[:button_class]
      assert_includes cancel[:form_data][:confirm], "Cancelar o pedido"
    end

    test "lifecycle inserts a delivery problem branch step" do
      steps = order_in("delivery_issue").lifecycle
      branch = steps.find { |step| step.classes == "branch current" }
      assert_equal "Problema na entrega", branch.label
    end

    test "status_description for delivery_issue is the admin copy" do
      assert_equal I18n.t("admin.orders.states.delivery_issue.description"),
                   order_in("delivery_issue").status_description
    end

    test "history is newest-first and labels actor vs automatic" do
      presenter = order_in("awaiting_payment")
      presenter.order.transition_to!("payment_confirmed", actor: users(:admin))
      history = OrderPresenter.new(presenter.order.reload).history

      assert_equal "payment_confirmed", history.first[:status]
      assert_equal I18n.t("admin.orders.detail.by", name: users(:admin).full_name), history.first[:by]
      assert_equal I18n.t("admin.orders.detail.automatic"), history.last[:by]
    end

    test "payment badge for a paid Pix order" do
      presenter = order_in("payment_confirmed")
      presenter.order.update!(payment_method: "pix")
      payment = OrderPresenter.new(presenter.order.reload).payment

      assert_equal "Pix", payment.method_label
      assert_equal "bi-cash-coin", payment.icon
      assert_equal "paid", payment.status_class
      assert_equal "bi-check-circle-fill", payment.status_icon
    end

    test "payment badge shows an unknown-method label when no method is set" do
      payment = order_in("awaiting_payment").payment
      assert_equal "Forma de pagamento não identificada", payment.method_label
      assert_equal "bi-wallet2", payment.icon
      assert_equal "pending", payment.status_class
      assert_equal "bi-hourglass-split", payment.status_icon
    end

    test "customer contact details are formatted" do
      presenter = order_in("payment_confirmed")
      assert_equal "111.444.777-35", presenter.customer_cpf
      assert_equal "(11) 99999-8888", presenter.customer_phone
      assert_includes 0..7, presenter.avatar_tint_index
    end

    test "tracking events come newest-first from the shipment" do
      presenter = OrderPresenter.new(orders(:shipped_order))
      events = presenter.tracking_events
      assert_equal %w[DO PO], events.map(&:event_code)
    end

    test "an order with no label in flight leaves the lifecycle and the actions alone" do
      presenter = OrderPresenter.new(orders(:producing))

      assert_not presenter.label_in_flight?
      assert_not presenter.label_retryable?
      assert_equal "idle", presenter.label_feedback.state
      assert_nil presenter.lifecycle.find { |step| step.doing }
    end

    test "the etiqueta step goes pending while the label is being emitted" do
      order = orders(:producing)
      label = order.shipment.create_shipping_label!(state: :pending)
      presenter = OrderPresenter.new(order.reload)

      assert presenter.label_in_flight?
      step = presenter.lifecycle.find { |entry| entry.doing }
      assert_equal I18n.t("admin.orders.lifecycle.label_issued"), step.label
      assert_equal I18n.t("admin.orders.lifecycle.doing_queued"), step.doing
      assert_equal "pending", step.classes
      assert_nil step.auto_note

      label.update!(state: :requesting)
      doing = OrderPresenter.new(order.reload).lifecycle.find { |entry| entry.doing }.doing
      assert_equal I18n.t("admin.orders.lifecycle.doing_running"), doing
    end

    test "a failed label is retryable without being in flight" do
      order = orders(:producing)
      order.shipment.create_shipping_label!(state: :prepost_confirmed).record_error!("PPN-320")
      presenter = OrderPresenter.new(order.reload)

      assert presenter.label_retryable?
      assert_not presenter.label_in_flight?
    end
  end
end
