class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.references :user, null: false, foreign_key: true

      # Human-facing order number (PG-YYYYMMDD#### — date + four random digits).
      # Generated in Order#assign_number; the unique index below is the backstop.
      t.string :number, null: false

      # Customer-facing lifecycle (docs/architecture.md § 4). String-backed so the
      # DB row reads the same as the account.orders.states.<status> locale keys.
      t.string :status, null: false, default: "aguardando_pagamento"

      # Money snapshot, in cents — an order is a historical record, so totals are
      # frozen at checkout and never recomputed from the live catalog.
      t.integer :subtotal_cents, null: false
      t.integer :shipping_cents, null: false
      t.integer :total_cents,    null: false

      # Chosen Correios service (sedex / pac / mini_envios), re-quoted server-side
      # at checkout; shipping_cents is that quote's price.
      t.string :shipping_service, null: false

      # Shipping address snapshot. Copied off the customer's saved Address at
      # checkout so a later edit/delete of that Address can't mutate this order
      # (mirrors the prepostagem destinatario block; see CreateAddresses).
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
