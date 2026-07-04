module Production
  class EligibleOrders
    STATUSES = %w[payment_confirmed awaiting_components production_issue].freeze

    def self.within(from: nil, to: nil)
      new(from: from, to: to).relation
    end

    def initialize(from: nil, to: nil)
      @from = from
      @to = to
    end

    def relation
      period_range ? base.where(created_at: period_range) : base
    end

    private

    def base
      Order.where(status: STATUSES)
           .where(id: OrderItem.games.select(:order_id))
           .includes(:user, order_items: { product: :category })
           .order(created_at: :asc)
    end

    def period_range
      return unless @from || @to

      lower_bound..upper_bound
    end

    def lower_bound
      @from.in_time_zone.beginning_of_day if @from
    end

    def upper_bound
      @to.in_time_zone.end_of_day if @to
    end
  end
end
