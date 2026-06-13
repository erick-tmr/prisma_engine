class CreateOrderItems < ActiveRecord::Migration[8.1]
  def change
    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.references :product, null: true, foreign_key: { on_delete: :nullify }

      t.string  :name,             null: false
      t.integer :unit_price_cents, null: false
      t.integer :quantity,         null: false
      t.jsonb   :chosen_options,   null: false, default: []
      t.string  :photo_path

      t.timestamps
    end
  end
end
