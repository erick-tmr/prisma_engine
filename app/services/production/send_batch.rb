module Production
  class SendBatch
    def self.call(orders:, operator:, from: nil, to: nil)
      new(orders: orders, operator: operator, from: from, to: to).call
    end

    def initialize(orders:, operator:, from: nil, to: nil)
      @orders = orders.to_a
      @operator = operator
      @from = from
      @to = to
    end

    def call
      Order.transaction do
        batch = record_batch
        @orders.each { |order| order.transition_to!("in_production", actor: @operator) }
        Order.where(id: @orders.map(&:id)).update_all(production_batch_id: batch.id)
        batch
      end
    end

    private

    def record_batch
      ProductionBatch.create!(operator: @operator, period_from: @from, period_to: @to, orders_count: @orders.size)
    end
  end
end
