module Admin
  class OrderPresenter
    FLOW = %w[awaiting_payment payment_confirmed in_production label_issued shipped delivered].freeze

    BRANCH_ANCHOR = {
      "awaiting_components" => "payment_confirmed",
      "production_issue"    => "in_production",
      "delivery_issue"      => "shipped",
      "awaiting_return"     => "delivered",
      "returning"           => "delivered",
      "returned"            => "shipped",
      "cancelled"           => "awaiting_payment",
      "merged"              => "payment_confirmed"
    }.freeze

    AUTO_FLOW_NOTE = {
      "payment_confirmed" => "webhook",
      "shipped"           => "correios",
      "delivered"         => "correios"
    }.freeze

    AUTO_NEXT_STATUSES = %w[label_issued shipped delivered awaiting_return returning cancelled].freeze

    PAYMENT_METHOD_LABELS = { "pix" => "Pix", "credit_card" => "Cartão de crédito" }.freeze
    PAYMENT_METHOD_ICONS = { "pix" => "bi-cash-coin", "credit_card" => "bi-credit-card" }.freeze

    LifecycleStep = Data.define(:label, :classes, :auto_note, :doing)
    Payment = Data.define(:method_label, :icon, :status_class, :status_icon, :status_label)

    def initialize(order)
      @order = order
    end

    attr_reader :order

    delegate :number, :status, :order_items, :subtotal_cents, :total_cents,
             :placed_at, :payment_method, :shipping_visible?, :observation,
             :merged?, :merged_into, to: :order

    def status_label(value = status)
      I18n.t("account.orders.states.#{value}.label")
    end

    def status_description
      I18n.t("admin.orders.states.#{status}.description")
    end

    def item_count
      order_items.sum(&:quantity)
    end

    def shipping_cents
      order.shipment.shipping_cents
    end

    def shipping_service_label
      order.shipment.service_label
    end

    def address
      order.shipment.address
    end

    def receiver_obs
      order.shipment&.receiver_obs
    end

    def payment
      if order.payment_status == :paid
        payment_badge("paid", "bi-check-circle-fill", I18n.t("admin.orders.detail.payment_confirmed"))
      else
        payment_badge("pending", "bi-hourglass-split", I18n.t("admin.orders.detail.payment_pending"))
      end
    end

    def tracking_events
      order.tracking_events.sort_by(&:occurred_at).reverse
    end

    def tracking_code
      order.shipment&.tracking_code
    end

    def tracking_url
      order.shipment&.tracking_url
    end

    def available_actions
      OrderActions.available_for(status).each_with_index.map do |action, index|
        {
          id: action.id,
          icon: action.icon,
          label: I18n.t("admin.dashboard.bulk_actions.#{action.id}"),
          target_label: status_label(action.to),
          button_class: button_class(action, index),
          form_data: action.danger ? { confirm: I18n.t("admin.orders.detail.cancel_confirm", number: number) } : {}
        }
      end
    end

    def auto_next_note
      return unless AUTO_NEXT_STATUSES.include?(status)

      I18n.t("admin.orders.auto_next.#{status}")
    end

    def label_printable?
      order.label_issued? && !!order.shipping_label&.ready?
    end

    def label_feedback
      @label_feedback ||= LabelFeedback.new(order)
    end

    def return_startable?
      Shipping::StartReturn::SOURCES.include?(status) && order.shipment.present? && order.return_shipment.nil?
    end

    def return_abortable?
      return false unless Shipping::CancelReturn::SOURCES.include?(status)

      shipment = order.return_shipment
      shipment.present? && shipment.posted_at.nil?
    end

    def return_reason
      order.return_reason
    end

    def return_label_printable?
      !!order.return_shipping_label&.ready?
    end

    def label_in_flight?
      label_feedback.in_flight?
    end

    def label_retryable?
      label_feedback.failed?
    end

    def lifecycle
      anchor = BRANCH_ANCHOR[status]
      branch = anchor.present? && FLOW.exclude?(status)
      current = FLOW.index(branch ? anchor : status)
      steps = FLOW.each_with_index.map { |step, index| flow_step(step, index, current) }
      branch ? with_branch_step(steps, current) : steps
    end

    def history
      order.status_changes.sort_by { |change| [ change.created_at, change.id ] }.reverse.map do |change|
        {
          status: change.to_status,
          label: status_label(change.to_status),
          by: actor_label(change),
          at: change.created_at
        }
      end
    end

    def customer
      order.user
    end

    def customer_cpf
      customer.cpf.to_s.gsub(/\A(\d{3})(\d{3})(\d{3})(\d{2})\z/, '\1.\2.\3-\4')
    end

    def customer_phone
      PhoneFormat.call(customer.phone)
    end

    def avatar_tint_index
      AvatarTint.index_for(customer.full_name)
    end

    private

    def actor_label(change)
      return I18n.t("admin.orders.detail.automatic") if change.automatic || change.actor.nil?

      I18n.t("admin.orders.detail.by", name: change.actor.full_name)
    end

    def payment_badge(status_class, status_icon, status_label)
      Payment.new(
        method_label: PAYMENT_METHOD_LABELS.fetch(payment_method.to_s, I18n.t("admin.orders.detail.payment_method_unknown")),
        icon: PAYMENT_METHOD_ICONS.fetch(payment_method.to_s, "bi-wallet2"),
        status_class: status_class, status_icon: status_icon, status_label: status_label
      )
    end

    def button_class(action, index)
      return "act-btn danger" if action.danger
      return "act-btn primary" if index.zero?

      "act-btn"
    end

    def with_branch_step(steps, current)
      steps[current] = steps[current].with(classes: "done")
      steps.insert(current + 1, LifecycleStep.new(label: status_label, classes: "branch current", auto_note: nil, doing: nil))
      steps
    end

    def flow_step(step, index, current)
      doing = step == "label_issued" ? doing_note : nil
      LifecycleStep.new(
        label: lifecycle_label(step),
        classes: doing ? "pending" : step_class(index, current),
        auto_note: doing ? nil : flow_auto_note(step),
        doing: doing
      )
    end

    def doing_note
      return unless label_in_flight?

      I18n.t("admin.orders.lifecycle.doing_#{label_feedback.state}")
    end

    def step_class(index, current)
      return "done" if index < current
      return "current" if index == current

      "upcoming"
    end

    def flow_auto_note(step)
      key = AUTO_FLOW_NOTE[step]
      key && I18n.t("admin.orders.lifecycle.auto_#{key}")
    end

    def lifecycle_label(step)
      I18n.t("admin.orders.lifecycle.#{step}")
    end
  end
end
