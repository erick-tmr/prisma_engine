class AddDceToShippingLabels < ActiveRecord::Migration[8.1]
  def change
    add_column :shipping_labels, :dce_base64, :text
    add_column :shipping_labels, :dce_filename, :string
  end
end
