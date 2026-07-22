class RemovePhotoPathFromOrderItems < ActiveRecord::Migration[8.1]
  def change
    remove_column :order_items, :photo_path, :string
  end
end
