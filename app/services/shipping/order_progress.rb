module Shipping
  # Translates a freshly-synced shipment's tracking_state into the order's
  # lifecycle, walking the linear shipping leg (label_issued → shipped →
  # delivered) one OrderStatusChange at a time so a poll that jumps straight to
  # delivered still records the intermediate shipped step. A terminal delivery
  # problem (returned) walks the order to shipped and then to delivery_issue.
  #
  # Idempotent and guard-driven: an order already at or past the target, or one
  # sitting off the shipping leg (cancelled, awaiting_refund, …), is left
  # untouched, so no transition_to! ever hits its raise branch and the caller
  # needs no rescue.
  class OrderProgress
    LEG = %w[label_issued shipped delivered].freeze

    # tracking_state → how far along LEG the order should be, plus an optional
    # branch status reached from the end of that walk.
    TARGETS = {
      "in_transit" => { advance_to: "shipped",   then_to: nil },
      "delivered"  => { advance_to: "delivered", then_to: nil },
      "returned"   => { advance_to: "shipped",   then_to: "delivery_issue" }
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
        walk_to(plan[:advance_to])
        branch_to(plan[:then_to])
      end
    end

    private

    attr_reader :shipment, :order

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
