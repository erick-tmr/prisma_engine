class CreateOrderStatusChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :order_status_changes do |t|
      t.references :order, null: false, foreign_key: true
      t.references :actor, null: true, foreign_key: { to_table: :users }
      t.string :from_status
      t.string :to_status, null: false
      t.boolean :automatic, null: false, default: false

      t.timestamps
    end
  end
end
