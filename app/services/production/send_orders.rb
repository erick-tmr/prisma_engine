module Production
  class SendOrders
    def self.call(orders:, operator:)
      new(orders: orders, operator: operator).call
    end

    def initialize(orders:, operator:)
      @orders = orders.to_a
      @operator = operator
    end

    def call
      Order.transaction do
        entering.each { |order| order.transition_to!("in_production", actor: @operator) }
      end
      @orders
    end

    private

    def entering
      @orders.select { |order| EligibleOrders::ENTERING.include?(order.status) }
    end
  end
end
