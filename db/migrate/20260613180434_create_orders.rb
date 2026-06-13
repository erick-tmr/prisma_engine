class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.references :user, null: false, foreign_key: true

      t.string :number, null: false
      t.string :status, null: false, default: "aguardando_pagamento"

      t.integer :subtotal_cents, null: false
      t.integer :shipping_cents, null: false
      t.integer :total_cents,    null: false

      t.string :shipping_service, null: false

      t.string :ship_receiver_name, null: false
      t.string :ship_receiver_cpf,  null: false
      t.string :ship_zip,           null: false
      t.string :ship_street,        null: false
      t.string :ship_number,        null: false
      t.string :ship_complement
      t.string :ship_neighborhood,  null: false
      t.string :ship_city,          null: false
      t.string :ship_state,         null: false

      t.timestamps
    end

    add_index :orders, :number, unique: true
    add_index :orders, [ :user_id, :created_at ]
  end
end
