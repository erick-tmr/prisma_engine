class MoveShippingDataToShipments < ActiveRecord::Migration[8.1]
  def change
    change_table :shipments, bulk: true do |t|
      t.string :receiver_name
      t.string :receiver_cpf
      t.string :zip
      t.string :street
      t.string :number
      t.string :complement
      t.string :neighborhood
      t.string :city
      t.string :state
      t.integer :shipping_cents
    end
    change_column_null :shipments, :tracking_code, true

    change_table :orders, bulk: true do |t|
      t.remove :ship_receiver_name, type: :string
      t.remove :ship_receiver_cpf, type: :string
      t.remove :ship_zip, type: :string
      t.remove :ship_street, type: :string
      t.remove :ship_number, type: :string
      t.remove :ship_complement, type: :string
      t.remove :ship_neighborhood, type: :string
      t.remove :ship_city, type: :string
      t.remove :ship_state, type: :string
      t.remove :shipping_service, type: :string
      t.remove :shipping_cents, type: :integer
    end
  end
end
