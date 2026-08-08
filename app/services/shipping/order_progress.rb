module Shipping
  class OrderProgress
    LEG = %w[label_issued shipped delivered].freeze

    TARGETS = {
      "in_transit"     => { advance_to: "shipped",   then_to: nil },
      "delivered"      => { advance_to: "delivered", then_to: nil },
      "returned"       => { advance_to: "shipped",   then_to: "delivery_issue" },
      "delivery_issue" => { advance_to: "shipped",   then_to: "delivery_issue" }
    }.freeze

    def self.apply(shipment)
      new(shipment).apply
    end

    def initialize(shipment)
      @shipment = shipment
      @order = shipment.order
    end

    def apply
      plan = TARGETS[shipment.tracking_state]
      return unless plan

      Order.transaction do
        resume_from_issue
        walk_to(plan[:advance_to])
        branch_to(plan[:then_to])
      end
    end

    private

    attr_reader :shipment, :order

    def resume_from_issue
      return unless order.delivery_issue? && shipment.tracking_delivered?

      order.transition_to!("delivered", automatic: true)
    end

    def walk_to(target)
      target_index = LEG.index(target)
      while (current = LEG.index(order.status)) && current < target_index
        order.transition_to!(LEG[current + 1], automatic: true)
      end
    end

    def branch_to(target)
      return unless target && order.status == "shipped"

      order.transition_to!(target, automatic: true)
    end
  end
end
