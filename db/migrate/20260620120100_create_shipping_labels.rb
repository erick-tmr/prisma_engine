class CreateShippingLabels < ActiveRecord::Migration[8.1]
  def change
    create_table :shipping_labels do |t|
      t.references :shipment, null: false, foreign_key: true, index: { unique: true }
      t.integer :state, null: false, default: 0
      t.string :recibo_id
      t.string :filename
      t.text :pdf_base64
      t.string :error
      t.datetime :errored_at

      t.timestamps
    end
  end
end
