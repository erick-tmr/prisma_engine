class CreateProductionBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :production_batches do |t|
      t.references :operator, null: true, foreign_key: { to_table: :users }
      t.date :period_from
      t.date :period_to
      t.integer :orders_count, null: false, default: 0

      t.timestamps
    end

    add_reference :orders, :production_batch, null: true, foreign_key: { on_delete: :nullify }
  end
end
