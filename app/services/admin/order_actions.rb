module Admin
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
      Action.new(id: "cancel", from: Order::CANCELLABLE_STATUSES,
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
