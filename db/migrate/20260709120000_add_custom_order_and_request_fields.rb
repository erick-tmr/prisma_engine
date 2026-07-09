class AddCustomOrderAndRequestFields < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :custom_order, :boolean
    add_column :order_items, :requested_game, :string
    add_column :order_items, :request_notes, :text
  end
end
