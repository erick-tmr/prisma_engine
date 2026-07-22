class CreateCustomOrderForms < ActiveRecord::Migration[8.1]
  def change
    create_table :custom_order_forms do |t|
      t.references :product, null: false, foreign_key: true, index: { unique: true }
      t.string :title, limit: 60
      t.string :subtitle, limit: 180
      t.string :game_label, limit: 40
      t.string :game_placeholder, limit: 80
      t.string :game_hint, limit: 120
      t.string :game_error, limit: 120
      t.string :notes_label, limit: 40
      t.string :notes_placeholder, limit: 120

      t.timestamps
    end
  end
end
