class CreateOptionTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :option_types do |t|
      t.string  :name, null: false
      t.string  :slug, null: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :option_types, :slug, unique: true
  end
end
