module Admin
  class OrderPresenter
    FLOW = %w[awaiting_payment payment_confirmed in_production label_issued shipped delivered].freeze
    RETURN_FLOW = [ "delivered", *Shipping::RETURN_WALK ].freeze
    RETURN_AUTO_NOTE = { "returning" => "auto_posting", "returned" => "auto_arrival" }.freeze

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

    AUTO_NEXT_STATUSES = %w[label_issued shipped delivered delivery_issue
                            awaiting_return returning cancelled].freeze

    PAYMENT_METHOD_LABELS = { "pix" => "Pix", "credit_card" => "Cartão de crédito" }.freeze
    PAYMENT_METHOD_ICONS = { "pix" => "bi-cash-coin", "credit_card" => "bi-credit-card" }.freeze

    LifecycleStep = Data.define(:label, :classes, :auto_note, :doing, :wait) do
      def initialize(label:, classes:, auto_note: nil, doing: nil, wait: nil)
        super
      end
    end
    Payment = Data.define(:method_label, :icon, :status_class, :status_icon, :status_label)

    def initialize(order)
      @order = order
    end

    attr_reader :order

    delegate :number, :status, :order_items, :subtotal_cents, :total_cents,
             :placed_at, :payment_method, :observation,
             :merged?, :merged_into, to: :order

    def status_label(value = status)
      I18n.t("account.orders.states.#{value}.label")
    end

    def status_description
      charge_state = order.awaiting_return? && return_freight&.charge&.state
      variant = %w[pending expired].include?(charge_state) ? "description_charge_#{charge_state}" : "description"
      I18n.t("admin.orders.states.#{status}.#{variant}")
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

    def shipment_tracks
      %w[outbound inbound].filter_map { |direction| ShipmentTrack.for(order, direction) }
    end

    def available_actions
      OrderActions.available_for(status).map do |action|
        {
          id: action.id,
          icon: action.icon,
          label: I18n.t("admin.dashboard.bulk_actions.#{action.id}"),
          target_label: status_label(action.to),
          button_class: button_class(action),
          form_data: action.danger ? { confirm: I18n.t("admin.orders.detail.cancel_confirm", number: number) } : {}
        }
      end
    end

    def auto_next_note
      return unless AUTO_NEXT_STATUSES.include?(status)

      I18n.t("admin.orders.auto_next.#{status}")
    end

    def label_printable?
      order.label_issued? && !!order.shipping_label&.ready? && !label_feedback.expired?
    end

    def label_feedback
      @label_feedback ||= LabelFeedback.new(order)
    end

    def merge_panel
      MergePanel.new(order)
    end

    def stranded_merge
      plan = order.order_merge
      plan if plan&.pending? && !order.unpaid? && !merged?
    end

    def return_startable?
      Shipping::StartReturn::SOURCES.include?(status) && order.shipment.present? && order.return_shipment.nil?
    end

    def reshippable?
      Shipping::Reship.reshippable?(order)
    end

    def return_abortable?
      return false unless Shipping::CancelReturn::SOURCES.include?(status)

      shipment = order.return_shipment
      shipment.present? && shipment.posted_at.nil?
    end

    def return_recorded?
      order.return_shipment.present?
    end

    def return_reason
      order.return_reason
    end

    def return_freight
      shipment = order.return_shipment
      @return_freight ||= ReturnFreight.new(shipment) if shipment
    end

    def cancel_return_note
      freight = return_freight
      return unless freight&.paid? || freight&.expired?

      I18n.t("admin.orders.detail.return_freight.cancel_#{freight.paid? ? 'paid' : 'expired'}_to")
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
      order.return_leg? && order.return_shipment ? return_lifecycle : flow_lifecycle
    end

    def history
      order.status_changes.sort_by { |change| [ change.created_at, change.id ] }.reverse.map do |change|
        {
          status: change.to_status,
          label: status_label(change.to_status),
          by: actor_label(change),
          at: change.created_at,
          note: merge_note(change)
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

    def merge_note(change)
      plan = change.order_merge
      return unless plan

      I18n.t("admin.orders.merge.history_note", numbers: plan.folded_orders.pluck(:number).join(", "))
    end

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

    def button_class(action)
      action.danger ? "act-btn danger" : "act-btn primary"
    end

    def flow_lifecycle
      anchor = BRANCH_ANCHOR[status]
      branch = anchor.present? && FLOW.exclude?(status)
      current = FLOW.index(branch ? anchor : status)
      steps = FLOW.each_with_index.map { |step, index| flow_step(step, index, current) }
      branch ? with_branch_step(steps, current) : steps
    end

    def return_lifecycle
      current = RETURN_FLOW.index(status)
      RETURN_FLOW.each_with_index.map do |step, index|
        next current_return_step(step) if index == current

        index < current ? LifecycleStep.new(label: return_step_label(step), classes: "done") : upcoming_return_step(step)
      end
    end

    def upcoming_return_step(step)
      note = RETURN_AUTO_NOTE[step] unless return_freight.expired?
      LifecycleStep.new(label: return_step_label(step), classes: "upcoming",
                        auto_note: note && I18n.t("admin.orders.lifecycle.#{note}"))
    end

    def current_return_step(step)
      label = return_step_label(step)
      freight = return_freight
      if (doing = step == "awaiting_return" && doing_note)
        LifecycleStep.new(label: label, classes: "pending", doing: doing)
      elsif freight.pending?
        LifecycleStep.new(label: label, classes: "wait current", wait: I18n.t("admin.orders.lifecycle.wait_freight"))
      elsif freight.expired?
        LifecycleStep.new(label: label, classes: "branch current", auto_note: I18n.t("admin.orders.lifecycle.freight_expired"))
      else
        LifecycleStep.new(label: label, classes: "current")
      end
    end

    def return_step_label(step)
      step == "delivered" ? lifecycle_label(step) : status_label(step)
    end

    def with_branch_step(steps, current)
      steps[current] = steps[current].with(classes: "done")
      steps.insert(current + 1, LifecycleStep.new(label: status_label, classes: "branch current"))
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
