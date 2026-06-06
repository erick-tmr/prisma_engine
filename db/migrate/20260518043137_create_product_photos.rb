class CreateProductPhotos < ActiveRecord::Migration[8.1]
  def change
    create_table :product_photos do |t|
      t.references :product, null: false, foreign_key: true
      t.string  :alt_text
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
