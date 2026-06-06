class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.references :category, null: false, foreign_key: true
      t.string  :name, null: false
      t.string  :slug, null: false
      t.text    :description
      t.integer :price_cents, null: false, default: 0
      t.string  :currency, null: false, default: "BRL"
      t.boolean :published, null: false, default: true
      t.string  :legacy_image_path

      t.timestamps
    end

    add_index :products, :slug, unique: true
    add_index :products, :published
  end
end
