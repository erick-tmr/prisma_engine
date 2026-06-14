class AddWebhookTokenToOrders < ActiveRecord::Migration[8.1]
  class MigrationOrder < ActiveRecord::Base
    self.table_name = "orders"
  end

  def up
    add_column :orders, :webhook_token, :string

    MigrationOrder.reset_column_information
    MigrationOrder.where(webhook_token: nil).find_each do |order|
      order.update_columns(webhook_token: SecureRandom.base58(24))
    end

    add_index :orders, :webhook_token, unique: true
  end

  def down
    remove_index :orders, :webhook_token
    remove_column :orders, :webhook_token
  end
end
