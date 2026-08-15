module Shipping
  class OrderProgress
    def self.apply(shipment)
      new(shipment).apply
    end

    def initialize(shipment)
      @shipment = shipment
      @order = shipment.order
      @progress = Shipping::Leg.for(shipment).progress
    end

    def apply
      plan = progress.targets[shipment.tracking_state]
      return warn_unmapped unless plan

      Order.transaction do
        resolve_issue
        walk_to(plan[:advance_to])
        branch_to(plan[:then_to])
      end
    end

    private

    attr_reader :shipment, :order, :progress

    def warn_unmapped
      return unless progress.notable_unmapped.include?(shipment.tracking_state)

      Rails.logger.warn(
        "[correios-rastro] unmapped #{shipment.direction} state=#{shipment.tracking_state} " \
        "tracking_code=#{shipment.tracking_code} order=#{order.number}"
      )
    end

    # A flagged order leaves delivery_issue only once tracking says the object
    # stopped waiting: the customer collected it, or it came back to us.
    def resolve_issue
      target = progress.resolutions[shipment.tracking_state]
      return unless target && order.status == progress.issue_status

      order.transition_to!(target, automatic: true)
    end

    def walk_to(target)
      walk = progress.walk
      target_index = walk.index(target)
      while (current = walk.index(order.status)) && current < target_index
        order.transition_to!(walk[current + 1], automatic: true)
      end
    end

    def branch_to(target)
      return unless target && order.status == progress.branch_status

      order.transition_to!(target, automatic: true)
    end
  end
end
