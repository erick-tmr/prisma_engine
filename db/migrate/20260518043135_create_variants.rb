class CreateVariants < ActiveRecord::Migration[8.1]
  def change
    create_table :variants do |t|
      t.references :product, null: false, foreign_key: true
      t.string  :sku, null: false
      t.integer :price_cents, null: false, default: 0
      t.integer :price_modifier_cents
      t.boolean :available, null: false, default: true
      t.boolean :is_master, null: false, default: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :variants, :sku, unique: true
    add_index :variants, :product_id,
              unique: true,
              where: "is_master = true",
              name: "index_variants_one_master_per_product"
  end
end
