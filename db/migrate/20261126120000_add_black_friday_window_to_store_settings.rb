class AddBlackFridayWindowToStoreSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :store_settings, :black_friday_starts_at, :datetime
    add_column :store_settings, :black_friday_ends_at, :datetime

    up_only do
      execute <<~SQL.squish
        UPDATE store_settings
        SET black_friday_starts_at = '2026-11-27 03:00:00',
            black_friday_ends_at   = '2026-12-01 03:00:00'
      SQL
    end
  end
end
