module Admin
  # Canonical list of the manual status transitions an operator can drive from the
  # order detail screen. Mirrors Order::TRANSITIONS (and the mocked dashboard.js
  # ACTIONS): system/customer transitions (payment webhook, Correios shipped /
  # delivered, a customer's refund request) are deliberately not here.
  module OrderActions
    Action = Data.define(:id, :from, :to, :icon, :danger) do
      def available_for?(status)
        from.include?(status)
      end
    end

    ALL = [
      Action.new(id: "to_components", from: %w[payment_confirmed],
                 to: "awaiting_components", icon: "bi-box-seam", danger: false),
      Action.new(id: "flag_issue", from: %w[in_production],
                 to: "production_issue", icon: "bi-exclamation-triangle", danger: false),
      Action.new(id: "refund_done", from: %w[awaiting_refund],
                 to: "cancelled", icon: "bi-cash-coin", danger: false),
      Action.new(id: "cancel", from: %w[awaiting_payment],
                 to: "cancelled", icon: "bi-x-circle", danger: true),
      Action.new(id: "issue_refund", from: %w[delivery_issue],
                 to: "awaiting_refund", icon: "bi-arrow-counterclockwise", danger: false),
      Action.new(id: "reship", from: %w[delivery_issue],
                 to: "shipped", icon: "bi-truck", danger: false),
      Action.new(id: "cancel_issue", from: %w[delivery_issue],
                 to: "cancelled", icon: "bi-x-circle", danger: true)
    ].freeze

    def self.lookup(id)
      ALL.find { |action| action.id == id }
    end

    def self.available_for(status)
      ALL.select { |action| action.available_for?(status) }
    end
  end
end
