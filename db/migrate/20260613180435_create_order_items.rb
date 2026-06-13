class CreateOrderItems < ActiveRecord::Migration[8.1]
  def change
    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true

      # Nullable on purpose: the catalog row is a convenience link (e.g. "buy
      # again"), not the source of truth. A product can be unpublished or deleted
      # later; nullify keeps the historical line item intact.
      t.references :product, null: true, foreign_key: { on_delete: :nullify }

      # Line snapshot — name, unit price, and chosen-option labels are frozen at
      # checkout so the order reflects what was actually bought, not the live
      # catalog. Mirrors the Cart::Line / Account::MockOrderItem shape.
      t.string  :name,             null: false
      t.integer :unit_price_cents, null: false
      t.integer :quantity,         null: false
      t.jsonb   :chosen_options,   null: false, default: []
      t.string  :photo_path

      t.timestamps
    end
  end
end
