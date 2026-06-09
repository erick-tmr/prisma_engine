class CreateGameOfTheMonths < ActiveRecord::Migration[8.1]
  def change
    create_table :game_of_the_months do |t|
      t.integer :year,  null: false
      t.integer :month, null: false
      t.text    :note

      t.timestamps
    end

    add_index :game_of_the_months, [ :year, :month ], unique: true
    add_check_constraint :game_of_the_months,
                         "month BETWEEN 1 AND 12",
                         name: "game_of_the_months_month_range"
  end
end
