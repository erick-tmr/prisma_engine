class AddPaymentFieldsToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :external_id, :string
    add_column :orders, :receipt_url, :string
    add_column :orders, :payment_method, :string

    add_index :orders, :external_id, unique: true
  end
end
