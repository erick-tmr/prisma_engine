class CreateBrindes < ActiveRecord::Migration[8.1]
  def change
    create_table :brindes do |t|
      t.references :game_of_the_month, null: false, foreign_key: true
      t.string  :caption
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
