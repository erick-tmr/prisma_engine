class AddRelabelAttemptsToShippingLabels < ActiveRecord::Migration[8.1]
  def change
    add_column :shipping_labels, :relabel_attempts, :integer, default: 0, null: false
  end
end
