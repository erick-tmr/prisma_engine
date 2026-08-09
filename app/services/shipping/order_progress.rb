module Shipping
  class OrderProgress
    LEG = %w[label_issued shipped delivered].freeze

    TARGETS = {
      "in_transit"     => { advance_to: "shipped",   then_to: nil },
      "delivered"      => { advance_to: "delivered", then_to: nil },
      "returned"       => { advance_to: "shipped",   then_to: "returned" },
      "delivery_issue" => { advance_to: "shipped",   then_to: "delivery_issue" }
    }.freeze

    # A flagged order leaves delivery_issue only once tracking says the object
    # stopped waiting: the customer collected it, or it came back to us.
    RESOLUTIONS = { "delivered" => "delivered", "returned" => "returned" }.freeze

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
        resolve_issue
        walk_to(plan[:advance_to])
        branch_to(plan[:then_to])
      end
    end

    private

    attr_reader :shipment, :order

    def resolve_issue
      target = RESOLUTIONS[shipment.tracking_state]
      return unless order.delivery_issue? && target

      order.transition_to!(target, automatic: true)
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
