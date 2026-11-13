class AddPaymentUrlToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :payment_url, :string
  end
end
