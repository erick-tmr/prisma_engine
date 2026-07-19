class AddCatalogSyncFieldsToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :catalog_synced_at, :datetime
    add_column :products, :catalog_sync_error, :string
    add_index :products, :catalog_synced_at
  end
end
