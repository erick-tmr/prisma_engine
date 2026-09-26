module Admin
  class MergeOrders
    ADDRESS_FIELDS = %i[zip street number complement].freeze

    Preview = Data.define(
      :master, :absorbed, :service_label, :combined_weight_grams, :combined_shipping_cents,
      :shipping_cents, :subtotal_cents, :observation, :settled_status, :address_mismatches, :voided_labels,
      :service
    ) do
      def total_cents
        subtotal_cents + shipping_cents
      end

      def item_count
        [ master, *absorbed ].sum { |order| order.order_items.sum(&:quantity) }
      end
    end

    Result = Data.define(:preview, :error) do
      def success?
        error.nil?
      end
    end

    def initialize(master:, numbers:)
      @master = master
      @numbers = Array(numbers).compact_blank.uniq
    end

    def preview
      return failure(:master_ineligible) unless eligible?(master)
      return failure(:nothing_selected) if numbers.empty?
      return failure(:ineligible) if absorbed.size < numbers.size

      build_preview
    rescue Correios::Api::Error
      failure(:shipping_error)
    end

    def call(actor:)
      result = preview
      return result unless result.success?

      executed = Order.transaction do
        plan = OrderMerge.create!(plan_attributes(result.preview))
        Orders::Merge.call(order_merge: plan, actor: actor)
        plan.reload.executed_at.present? || raise(ActiveRecord::Rollback)
      end
      executed ? result : failure(:ineligible)
    end

    private

    attr_reader :master, :numbers

    def failure(error)
      Result.new(preview: nil, error: error)
    end

    def eligible?(order)
      Orders::MergeEligibility.for(order, origin: :backoffice).ok?
    end

    def absorbed
      @absorbed ||= master.user.orders.where(number: numbers).where.not(id: master.id)
                          .includes(:order_items, shipment: :shipping_label)
                          .order(:created_at)
                          .select { |order| eligible?(order) }
    end

    def participants
      [ master, *absorbed ]
    end

    def build_preview
      weight = Shipping::CombinedWeight.call(orders: participants, cart: Cart::Bag.new)
      service = Shipping::CombinedService.call(orders: participants, weight_grams: weight)
      return failure(:shipping_unavailable) unless service

      Result.new(preview: preview_for(service, weight), error: nil)
    end

    def preview_for(service, weight)
      combined = service[:price_cents]
      Preview.new(
        master: master, absorbed: absorbed, service: service[:key].to_s, service_label: service[:label],
        combined_weight_grams: weight, combined_shipping_cents: combined,
        shipping_cents: [ combined, master.shipment.shipping_cents ].max,
        subtotal_cents: participants.sum(&:subtotal_cents),
        observation: Orders::MergedObservation.call(master: master, folded: absorbed),
        settled_status: Order.settled_merge_status(participants),
        address_mismatches: absorbed.reject { |order| same_address?(order) },
        voided_labels: participants.select { |order| order.shipment.shipping_label }
      )
    end

    def same_address?(order)
      destination(order.shipment) == destination(master.shipment)
    end

    def destination(shipment)
      shipment.address.slice(*ADDRESS_FIELDS).transform_values { |value| value.to_s.strip.downcase }
    end

    def plan_attributes(preview)
      {
        master_order:            master,
        absorbed_order_ids:      preview.absorbed.map(&:id),
        combined_weight_grams:   preview.combined_weight_grams,
        combined_service:        preview.service,
        combined_shipping_cents: preview.combined_shipping_cents,
        paid_fretes_cents:       participants.sum { |order| order.shipment.shipping_cents }
      }
    end
  end
end
