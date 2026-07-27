class AddBackofficeListIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :orders, :created_at
    add_index :orders, :status
    add_index :users, :full_name
    add_index :products, :name
  end
end
