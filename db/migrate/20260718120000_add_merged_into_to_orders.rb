class AddMergedIntoToOrders < ActiveRecord::Migration[8.1]
  def change
    add_reference :orders, :merged_into, foreign_key: { to_table: :orders }, null: true, index: true
  end
end
