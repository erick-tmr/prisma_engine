class OrderMerge < ApplicationRecord
  belongs_to :carrier_order, class_name: "Order"
  belongs_to :master_order, class_name: "Order"

  validates :combined_weight_grams, :combined_shipping_cents, :paid_fretes_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :combined_service, inclusion: { in: Shipping::SERVICES.keys.map(&:to_s) }

  def pending?
    executed_at.nil?
  end

  def absorbed_orders
    Order.where(id: absorbed_order_ids)
  end
end
