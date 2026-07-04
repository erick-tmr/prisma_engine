class AddObservationToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :observation, :text
  end
end
