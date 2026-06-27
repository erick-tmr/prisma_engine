module Admin
  class ProductionReportPresenter
    ELIGIBLE_STATUSES = OrderActions.lookup("to_production").from

    Row = Data.define(:seq, :customer, :number, :placed_on, :items)
    Item = Data.define(:quantity, :name, :variants)

    def initialize(from: nil, to: nil)
      @from = from
      @to = to
    end

    def orders
      @orders ||= scope.to_a
    end

    def count
      orders.size
    end

    def rows
      orders.each_with_index.map { |order, index| build_row(order, index) }
    end

    def period_clause
      return I18n.t("admin.production_report.period_all") unless @from || @to

      I18n.t("admin.production_report.period_range",
             dates: [ @from, @to ].compact.map { |date| I18n.l(date) }.join(" a "))
    end

    def from_iso
      @from&.iso8601
    end

    def to_iso
      @to&.iso8601
    end

    private

    def scope
      relation = Order.where(status: ELIGIBLE_STATUSES)
                      .where(id: OrderItem.games.select(:order_id))
                      .includes(:user, order_items: { product: :category })
                      .order(created_at: :asc)
      period_range ? relation.where(created_at: period_range) : relation
    end

    def period_range
      return unless @from || @to

      start_bound..end_bound
    end

    def start_bound
      @from.in_time_zone.beginning_of_day if @from
    end

    def end_bound
      @to.in_time_zone.end_of_day if @to
    end

    def build_row(order, index)
      Row.new(
        seq: index + 1,
        customer: order.user.full_name,
        number: order.number,
        placed_on: I18n.l(order.placed_at.to_date),
        items: order.order_items.select(&:game?).map { |item| build_item(item) }
      )
    end

    def build_item(item)
      Item.new(quantity: item.quantity, name: item.name, variants: variant_summary(item.chosen_options))
    end

    def variant_summary(chosen_options)
      chosen_options.map { |option| option.sub(/\A[^:]+:\s*/, "") }.join(" · ")
    end
  end
end
