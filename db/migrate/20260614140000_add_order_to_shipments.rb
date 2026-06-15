class AddOrderToShipments < ActiveRecord::Migration[8.1]
  def change
    add_reference :shipments, :order, null: false, foreign_key: true
  end
end
