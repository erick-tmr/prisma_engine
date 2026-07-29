class AddPublishSchedulingToGameOfTheMonths < ActiveRecord::Migration[8.1]
  def change
    add_column :game_of_the_months, :publish_at, :datetime
    add_column :game_of_the_months, :published_at, :datetime

    up_only do
      execute <<~SQL.squish
        UPDATE game_of_the_months
        SET publish_at   = make_timestamptz(year, month, 1, 0, 0, 0, 'America/Sao_Paulo'),
            published_at = make_timestamptz(year, month, 1, 0, 0, 0, 'America/Sao_Paulo')
      SQL
    end

    change_column_null :game_of_the_months, :publish_at, false
  end
end
