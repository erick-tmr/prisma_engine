class MoveBrindesToGameOfTheMonthProducts < ActiveRecord::Migration[8.1]
  def up
    add_reference :brindes, :game_of_the_month_product, foreign_key: true

    say_with_time "backfilling brindes.game_of_the_month_product_id" do
      Brinde.reset_column_information
      Brinde.unscoped.find_each do |brinde|
        target = GameOfTheMonthProduct.where(game_of_the_month_id: brinde.game_of_the_month_id)
                                       .order(:position, :id).first
        if target
          brinde.update_column(:game_of_the_month_product_id, target.id)
        else
          brinde.delete
        end
      end
    end

    change_column_null :brindes, :game_of_the_month_product_id, false
    remove_reference :brindes, :game_of_the_month, foreign_key: true, index: true
  end

  def down
    add_reference :brindes, :game_of_the_month, foreign_key: true

    say_with_time "restoring brindes.game_of_the_month_id" do
      Brinde.reset_column_information
      Brinde.unscoped.find_each do |brinde|
        target = GameOfTheMonthProduct.find_by(id: brinde.game_of_the_month_product_id)
        brinde.update_column(:game_of_the_month_id, target.game_of_the_month_id) if target
      end
    end

    change_column_null :brindes, :game_of_the_month_id, false
    remove_reference :brindes, :game_of_the_month_product, foreign_key: true, index: true
  end
end
