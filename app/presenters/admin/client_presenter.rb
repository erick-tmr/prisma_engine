module Admin
  class ClientPresenter
    Stats = Data.define(:orders, :cancelled, :paid, :spent_cents, :average_ticket_cents, :last_order)

    def initialize(client)
      @client = client
    end

    attr_reader :client

    delegate :id, :full_name, :email, :cpf, :phone, :created_at, to: :client

    def situation
      return "locked" if client.locked_at
      return "pending" if client.confirmed_at.nil?

      "active"
    end

    def avatar_tint_index
      AvatarTint.index_for(full_name)
    end

    def reference
      format("%04d", id)
    end

    def stats
      @stats ||= build_stats
    end

    def addresses
      @addresses ||= client.addresses.default_first.to_a
    end

    def ban
      @ban ||= Questions::Ban.new(client)
    end

    def strikes
      @strikes ||= client.question_strikes.chronological
                         .includes(:issued_by, question: { product: :category }).to_a
    end

    def ban_state
      return "perma" if ban.permanent?
      return "banned" if ban.active?
      return "served" if ban.strikes.positive?

      "clear"
    end

    def rung_state(rung)
      return "next" if rung[:reached_at].nil? && rung[:ordinal] == ban.strikes + 1
      return "upcoming" if rung[:reached_at].nil?

      rung[:ordinal] == [ ban.strikes, Questions::Ban::PERMANENT_AFTER ].min ? "spent current" : "spent"
    end

    private

    def build_stats
      paid = client.orders.paid
      paid_count = paid.count
      spent_cents = paid.sum(:total_cents)

      Stats.new(orders: client.orders.count, cancelled: client.orders.cancelled.count,
                paid: paid_count, spent_cents: spent_cents,
                average_ticket_cents: (spent_cents / paid_count if paid_count.positive?),
                last_order: client.orders.recent_first.first)
    end
  end
end
