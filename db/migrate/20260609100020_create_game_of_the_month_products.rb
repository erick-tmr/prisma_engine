class CreateGameOfTheMonthProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :game_of_the_month_products do |t|
      t.references :game_of_the_month, null: false, foreign_key: true
      t.references :product,            null: false, foreign_key: true
      t.integer    :position, null: false, default: 0

      t.timestamps
    end

    add_index :game_of_the_month_products,
              [ :game_of_the_month_id, :product_id ],
              unique: true,
              name: "index_gotm_products_on_month_and_product"
  end
end
