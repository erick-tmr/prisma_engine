class AddShippingWeightToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :shipping_weight_grams, :integer
  end
end
