class AddBlurbToGameOfTheMonthProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :game_of_the_month_products, :blurb, :text
  end
end
