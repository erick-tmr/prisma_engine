class CreateOrderMerges < ActiveRecord::Migration[8.1]
  def change
    create_table :order_merges do |t|
      t.references :carrier_order, null: false, foreign_key: { to_table: :orders }, index: { unique: true }
      t.references :master_order, null: false, foreign_key: { to_table: :orders }
      t.jsonb :absorbed_order_ids, null: false, default: []
      t.integer :combined_weight_grams, null: false
      t.string :combined_service, null: false
      t.integer :combined_shipping_cents, null: false
      t.integer :paid_fretes_cents, null: false
      t.datetime :executed_at

      t.timestamps
    end
  end
end
