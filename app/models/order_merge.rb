class OrderMerge < ApplicationRecord
  belongs_to :carrier_order, class_name: "Order", inverse_of: :order_merge, optional: true
  belongs_to :master_order, class_name: "Order"

  validates :combined_weight_grams, :combined_shipping_cents, :paid_fretes_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :combined_service, inclusion: { in: Shipping::SERVICES.keys.map(&:to_s) }

  scope :awaiting_carrier_payment, -> {
    where(executed_at: nil).where(carrier_order_id: Order.awaiting_payment.select(:id))
  }

  def self.involving(order)
    where(master_order_id: order.id).or(where("absorbed_order_ids @> ?", [ order.id ].to_json))
  end

  def pending?
    executed_at.nil?
  end

  def origin
    carrier_order_id ? :checkout : :backoffice
  end

  def absorbed_orders
    Order.where(id: absorbed_order_ids)
  end

  def folded_orders
    Order.where(id: [ carrier_order_id, *absorbed_order_ids ].compact, merged_into_id: master_order_id)
         .order(:created_at)
  end
end
