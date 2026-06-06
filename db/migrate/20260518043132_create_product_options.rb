class CreateProductOptions < ActiveRecord::Migration[8.1]
  def change
    create_table :product_options do |t|
      t.references :product, null: false, foreign_key: true
      t.string  :group_name
      t.string  :name, null: false
      t.integer :price_delta_cents, null: false, default: 0
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :product_options, [ :product_id, :group_name, :name ],
              unique: true,
              name: "index_product_options_uniqueness"
  end
end
