module Admin
  class ProductionReportPresenter
    Row = Data.define(:seq, :customer, :number, :placed_on, :items, :observation)
    Item = Data.define(:quantity, :name, :variants, :requested_game, :request_notes)

    CHARS_PER_LINE = 58

    def self.for_batch(batch)
      orders = batch.orders.includes(:user, :order_items).order(created_at: :asc)
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
      @rows ||= orders.each_with_index.map { |order, index| build_row(order, index) }
    end

    def column_break_seq
      weights = rows.map { |row| row_weight(row) }
      total = weights.sum
      filled = 0

      weights.each_with_index do |weight, index|
        filled += weight
        return index + 2 if filled * 2 >= total && index < weights.size - 1
      end

      nil
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
        items: order.order_items.sort_by(&:id).map { |item| build_item(item) },
        observation: order.observation
      )
    end

    def build_item(item)
      Item.new(
        quantity: item.quantity,
        name: item.name,
        variants: variant_values(item.chosen_options),
        requested_game: item.requested_game,
        request_notes: item.request_notes
      )
    end

    def row_weight(row)
      1 + text_lines(row.observation) + row.items.sum { |item| item_weight(item) }
    end

    def item_weight(item)
      1 + (item.requested_game.present? ? 1 : 0) + text_lines(item.request_notes)
    end

    def text_lines(text)
      return 0 if text.blank?

      text.split("\n").sum { |line| [ (line.length / CHARS_PER_LINE.to_f).ceil, 1 ].max }
    end

    def variant_values(chosen_options)
      chosen_options.map { |option| option.sub(/\A[^:]+:\s*/, "") }
    end
  end
end
