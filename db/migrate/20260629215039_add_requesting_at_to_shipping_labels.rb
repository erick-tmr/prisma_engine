class AddRequestingAtToShippingLabels < ActiveRecord::Migration[8.1]
  def change
    add_column :shipping_labels, :requesting_at, :datetime
  end
end
