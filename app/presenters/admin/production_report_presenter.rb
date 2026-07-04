module Admin
  class ProductionReportPresenter
    Row = Data.define(:seq, :customer, :number, :placed_on, :items, :observation)
    Item = Data.define(:quantity, :name, :variants)

    def self.for_batch(batch)
      orders = batch.orders.includes(:user, order_items: { product: :category }).order(created_at: :asc)
      new(orders: orders, from: batch.period_from, to: batch.period_to)
    end

    def initialize(orders:, from: nil, to: nil)
      @relation = orders
      @from = from
      @to = to
    end

    def orders
      @orders ||= @relation.to_a
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

    def build_row(order, index)
      Row.new(
        seq: index + 1,
        customer: order.user.full_name,
        number: order.number,
        placed_on: I18n.l(order.placed_at.to_date),
        items: order.order_items.select(&:game?).map { |item| build_item(item) },
        observation: order.observation
      )
    end

    def build_item(item)
      Item.new(quantity: item.quantity, name: item.name, variants: variant_values(item.chosen_options))
    end

    def variant_values(chosen_options)
      chosen_options.map { |option| option.sub(/\A[^:]+:\s*/, "") }
    end
  end
end
