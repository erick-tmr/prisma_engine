module Admin
  # Canonical list of the manual status transitions an operator can drive from the
  # order detail screen. Mirrors Order::TRANSITIONS (and the mocked dashboard.js
  # ACTIONS): system/customer transitions — payment webhook, Correios shipped /
  # delivered, a customer's refund request — are deliberately not here. `issue_label`
  # runs the real Correios pré-postagem saga; the others are plain transitions.
  module OrderActions
    Action = Data.define(:id, :from, :to, :icon, :danger, :saga) do
      def available_for?(status)
        from.include?(status)
      end
    end

    ALL = [
      Action.new(id: "to_production", from: %w[payment_confirmed awaiting_components production_issue],
                 to: "in_production", icon: "bi-tools", danger: false, saga: false),
      Action.new(id: "to_components", from: %w[payment_confirmed],
                 to: "awaiting_components", icon: "bi-box-seam", danger: false, saga: false),
      Action.new(id: "issue_label", from: %w[in_production],
                 to: "label_issued", icon: "bi-upc-scan", danger: false, saga: true),
      Action.new(id: "flag_issue", from: %w[in_production],
                 to: "production_issue", icon: "bi-exclamation-triangle", danger: false, saga: false),
      Action.new(id: "refund_done", from: %w[awaiting_refund],
                 to: "cancelled", icon: "bi-cash-coin", danger: false, saga: false),
      Action.new(id: "cancel", from: %w[awaiting_payment],
                 to: "cancelled", icon: "bi-x-circle", danger: true, saga: false)
    ].freeze

    def self.find(id)
      ALL.find { |action| action.id == id }
    end

    def self.available_for(status)
      ALL.select { |action| action.available_for?(status) }
    end
  end
end
