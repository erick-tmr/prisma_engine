class AddBlackFridayToHeroBanners < ActiveRecord::Migration[8.1]
  def change
    add_column :hero_banners, :black_friday, :boolean, default: false, null: false
  end
end
