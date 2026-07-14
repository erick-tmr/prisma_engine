class RemoveFaviconDataUriFromRecommendations < ActiveRecord::Migration[8.1]
  def change
    remove_column :recommendations, :favicon_data_uri, :text
  end
end
