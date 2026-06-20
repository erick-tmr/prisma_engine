class RemovePriceDeltaCentsFromProductOptions < ActiveRecord::Migration[8.1]
  def change
    remove_column :product_options, :price_delta_cents, :integer, default: 0, null: false
  end
end
