class DropProductionBatches < ActiveRecord::Migration[8.1]
  def change
    remove_reference :orders, :production_batch, foreign_key: { on_delete: :nullify }, index: true
    drop_table :production_batches do |t|
      t.references :operator, foreign_key: { to_table: :users }
      t.integer :orders_count, default: 0, null: false
      t.date :period_from
      t.date :period_to
      t.timestamps
    end
  end
end
