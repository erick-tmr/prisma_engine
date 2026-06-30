class CreateRecommendations < ActiveRecord::Migration[8.1]
  def change
    create_table :recommendations do |t|
      t.string   :url,             null: false
      t.string   :title,           null: false, default: ""
      t.string   :tagline,         null: false, default: ""
      t.string   :gradient,        null: false, default: ""
      t.text     :favicon_data_uri
      t.integer  :position,        null: false, default: 0
      t.boolean  :active,          null: false, default: true
      t.datetime :fetched_at

      t.timestamps
    end

    add_index :recommendations, :url, unique: true
  end
end
