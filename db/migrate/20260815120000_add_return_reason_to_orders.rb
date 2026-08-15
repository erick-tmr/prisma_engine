class AddReturnReasonToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :return_reason, :text
  end
end
