class AddSupersededAtToShipments < ActiveRecord::Migration[8.1]
  def change
    add_column :shipments, :superseded_at, :datetime
    remove_index :shipments, %i[order_id direction], unique: true
    add_index :shipments, %i[order_id direction], unique: true, where: "superseded_at IS NULL",
                                                  name: "index_shipments_on_order_id_and_direction_current"
  end
end
