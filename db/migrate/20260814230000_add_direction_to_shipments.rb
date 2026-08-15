class AddDirectionToShipments < ActiveRecord::Migration[8.1]
  def change
    add_column :shipments, :direction, :integer, default: 0, null: false
    remove_index :shipments, :order_id
    add_index :shipments, %i[order_id direction], unique: true
  end
end
