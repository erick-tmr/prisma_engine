class CreateReturnFreightCharges < ActiveRecord::Migration[8.1]
  def change
    create_table :return_freight_charges do |t|
      t.references :shipment, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.datetime :expires_at, null: false
      t.datetime :paid_at
      t.string :payment_method
      t.datetime :voided_at
      t.timestamps
    end
  end
end
