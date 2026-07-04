class CreateStoreSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :store_settings do |t|
      t.integer :handling_fee_cents, null: false, default: 300

      t.timestamps
    end
  end
end
