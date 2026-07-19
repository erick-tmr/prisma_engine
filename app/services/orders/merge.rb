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
        master  = order_merge.master_order.lock!
        carrier = order_merge.carrier_order.lock!
        consolidate(master, carrier) if mergeable_target?(master)
      end
    end

    private

    attr_reader :order_merge, :actor

    def consolidate(master, carrier)
      folded = [ carrier ]
      fold(carrier.lock!, master)
      folded.concat(absorb(master))
      recompute(master, folded)
      finalize(carrier, master)
      order_merge.update!(executed_at: Time.current)
    end

    def mergeable_target?(master)
      shipment = master.shipment
      return true if shipment && shipment.tracking_code.nil?

      Rails.logger.warn("Orders::Merge skipped ##{master.number}: master no longer accepts merges")
      false
    end

    def absorb(master)
      foldable, skipped = absorbed_orders.partition { |order| Order::MERGEABLE_STATUSES.include?(order.status) }
      skipped.each { |order| log_ineligible(order) }
      foldable.each { |order| fold_and_retire(order, master) }
      foldable
    end

    def absorbed_orders
      Order.where(id: order_merge.absorbed_order_ids).lock!.to_a
    end

    def log_ineligible(order)
      Rails.logger.warn("Orders::Merge skipped ##{order.number}: no longer eligible")
    end

    def fold_and_retire(order, master)
      fold(order, master)
      retire(order, master)
    end

    def fold(source, master)
      source.order_items.update_all(order_id: master.id)
    end

    def retire(order, master)
      order.shipment.destroy!
      order.update!(merged_into_id: master.id)
      order.transition_to!("merged", actor: actor, automatic: true)
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

    def finalize(carrier, master)
      retire(carrier, master)
    end
  end
end
