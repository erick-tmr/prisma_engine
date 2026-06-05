class CreateOptionValues < ActiveRecord::Migration[8.1]
  def change
    create_table :option_values do |t|
      t.references :option_type, null: false, foreign_key: true
      t.string  :name, null: false
      t.integer :price_contribution_cents, null: false, default: 0
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :option_values, [ :option_type_id, :name ], unique: true
  end
end
