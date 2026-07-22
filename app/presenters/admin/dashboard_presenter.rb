module Admin
  # Builds the backoffice dashboard's data island: the real Order / customer User
  # records the design renders, serialized as raw values (cents, ISO dates, digit
  # strings) so the formatting lives in one tested place, the JS module. Domain
  # vocabulary (status labels, bulk-action labels, situação labels) is pulled from
  # the locale so pt-BR copy stays single-sourced; the widget chrome (month names,
  # presets, pluralization) stays with the JS that owns it.
  class DashboardPresenter
    # Manual bulk transitions exposed in the order list, mirroring Order::TRANSITIONS.
    # System/customer-triggered transitions (payment webhook, Correios tracking, a
    # customer's refund request) are deliberately absent: see app/javascript/backoffice.
    BULK_ACTION_IDS = %w[to_components issue_label flag_issue refund_done cancel].freeze
    SITUATIONS = %w[active pending locked].freeze

    def orders
      @orders ||= load_orders
    end

    def clients
      @clients ||= load_clients
    end

    def reports
      @reports ||= load_reports
    end

    def to_h
      {
        "orders" => orders,
        "clients" => clients,
        "reports" => reports,
        "statuses" => Order::STATUSES,
        "statusLabels" => status_labels,
        "actionLabels" => action_labels,
        "situationLabels" => situation_labels
      }
    end

    def to_json(*)
      to_h.to_json
    end

    private

    def load_orders
      Order.includes(:user, :order_items, :shipment).recent_first.map do |order|
        {
          "n" => order.number,
          "clientName" => order.user.full_name,
          "city" => order.shipment&.city,
          "uf" => order.shipment&.state,
          "date" => order.created_at.strftime("%Y-%m-%d"),
          "status" => order.status,
          "total" => order.total_cents,
          "items" => order.order_items.sum(&:quantity)
        }
      end
    end

    def load_clients
      customers = User.where(admin: false).order(:full_name)
      ids = customers.map(&:id)
      order_counts = Order.where(user_id: ids).group(:user_id).count
      default_addresses = Address.where(user_id: ids, default: true).index_by(&:user_id)

      customers.map do |customer|
        address = default_addresses[customer.id]
        {
          "id" => customer.id,
          "name" => customer.full_name,
          "email" => customer.email,
          "cpf" => customer.cpf,
          "phone" => customer.phone,
          "city" => address&.city,
          "uf" => address&.state,
          "since" => customer.created_at.strftime("%Y-%m-%d"),
          "orders" => order_counts.fetch(customer.id, 0),
          "status" => situation(customer)
        }
      end
    end

    def load_reports
      ProductionBatch.includes(:operator).recent_first.map do |batch|
        {
          "id" => batch.id,
          "generatedAt" => I18n.l(batch.created_at),
          "operator" => batch.operator&.full_name || I18n.t("admin.production_report.report.system"),
          "orders" => batch.orders_count,
          "period" => report_period(batch),
          "url" => Rails.application.routes.url_helpers.admin_production_report_batch_path(batch)
        }
      end
    end

    def report_period(batch)
      from = batch.period_from
      to = batch.period_to
      return I18n.t("admin.production_report.report.all_periods") unless from || to

      [ from, to ].compact.map { |date| I18n.l(date) }.join(" a ")
    end

    def situation(customer)
      return "locked" if customer.locked_at?
      return "pending" if customer.confirmed_at.nil?

      "active"
    end

    def status_labels
      Order::STATUSES.index_with { |status| I18n.t("account.orders.states.#{status}.label") }
    end

    def action_labels
      BULK_ACTION_IDS.index_with { |id| I18n.t("admin.dashboard.bulk_actions.#{id}") }
    end

    def situation_labels
      SITUATIONS.index_with { |situation| I18n.t("admin.dashboard.situations.#{situation}") }
    end
  end
end
