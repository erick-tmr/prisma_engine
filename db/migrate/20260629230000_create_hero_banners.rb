class CreateHeroBanners < ActiveRecord::Migration[8.1]
  def change
    create_table :hero_banners do |t|
      t.string  :alt,      null: false, default: ""
      t.integer :position, null: false, default: 0
      t.boolean :active,   null: false, default: true

      t.timestamps
    end
  end
end
