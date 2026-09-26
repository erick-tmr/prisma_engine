class PrepareBackofficeOrderMerges < ActiveRecord::Migration[8.1]
  def change
    change_column_null :order_merges, :carrier_order_id, true
    add_reference :order_status_changes, :order_merge, foreign_key: true
  end
end
