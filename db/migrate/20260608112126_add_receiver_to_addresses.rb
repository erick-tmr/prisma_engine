class AddReceiverToAddresses < ActiveRecord::Migration[8.1]
  def up
    add_column :addresses, :receiver_name, :string
    add_column :addresses, :receiver_cpf,  :string

    # Backfill: pre-feature, every address's receiver was implicitly the
    # account holder. users.full_name and users.cpf are both NOT NULL, so
    # no row can stay NULL after this update.
    execute <<~SQL.squish
      UPDATE addresses
         SET receiver_name = users.full_name,
             receiver_cpf  = users.cpf
        FROM users
       WHERE addresses.user_id = users.id
    SQL

    change_column_null :addresses, :receiver_name, false
    change_column_null :addresses, :receiver_cpf,  false
  end

  def down
    remove_column :addresses, :receiver_cpf
    remove_column :addresses, :receiver_name
  end
end
