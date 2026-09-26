module Orders
  class Merge
    def self.call(order_merge:, actor: nil)
      new(order_merge: order_merge, actor: actor).call
    end

    def initialize(order_merge:, actor: nil)
      @order_merge = order_merge
      @actor = actor
    end

    def call
      return if order_merge.executed_at.present?

      Order.transaction do
        master = order_merge.master_order.lock!
        master.shipment&.lock!
        carrier = order_merge.carrier_order&.lock!
        consolidate(master, carrier) if mergeable_target?(master)
      end
    end

    private

    attr_reader :order_merge, :actor

    def origin
      order_merge.origin
    end

    def automatic?
      origin == :checkout
    end

    def consolidate(master, carrier)
      folded = [ carrier, *absorb ].compact
      target = Order.settled_merge_status([ master, *folded ])
      folded.each { |order| fold_and_retire(order, master) }
      void_label(master.shipment)
      recompute(master, folded)
      master.settle_after_merge!(target, order_merge: order_merge, actor: actor, automatic: automatic?)
      order_merge.update!(executed_at: Time.current)
    end

    def mergeable_target?(master)
      verdict = MergeEligibility.for(master, origin: origin)
      return true if verdict.ok?

      Rails.logger.warn("Orders::Merge skipped ##{master.number}: master no longer accepts merges (#{verdict.reason})")
      false
    end

    def absorb
      foldable, skipped = absorbed_orders.partition { |order| MergeEligibility.for(order, origin: origin).ok? }
      skipped.each { |order| log_ineligible(order) }
      foldable
    end

    def absorbed_orders
      Order.where(id: order_merge.absorbed_order_ids).lock!.to_a
    end

    def log_ineligible(order)
      Rails.logger.warn("Orders::Merge skipped ##{order.number}: no longer eligible")
    end

    def fold_and_retire(order, master)
      order.order_items.update_all(order_id: master.id)
      order.shipment.destroy!
      order.update!(merged_into_id: master.id)
      order.transition_to!("merged", actor: actor, automatic: automatic?)
    end

    def void_label(shipment)
      label = shipment.shipping_label
      return unless label

      shipment.tracking_events.delete_all
      shipment.reset_for_reissue
      shipment.save!
      label.destroy!
    end

    def recompute(master, folded)
      master.reload
      subtotal = master.order_items.sum("unit_price_cents * quantity")
      frete = [ order_merge.combined_shipping_cents, master.shipment.shipping_cents ].max
      master.shipment.update!(
        service:        order_merge.combined_service,
        weight_grams:   order_merge.combined_weight_grams,
        shipping_cents: frete
      )
      master.update!(
        subtotal_cents: subtotal,
        total_cents:    subtotal + frete,
        observation:    MergedObservation.call(master: master, folded: folded)
      )
    end
  end
end
