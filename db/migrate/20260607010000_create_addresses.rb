class CreateAddresses < ActiveRecord::Migration[8.1]
  def change
    create_table :addresses do |t|
      t.references :user, null: false, foreign_key: true
      # Mirrors the Correios prepostagem destinatario.endereco block — see
      # app/services/shipping/pre_postagem_request.rb.
      t.string :zip,          null: false # CEP — 8 digits, normalized before validation
      t.string :street,       null: false # logradouro
      t.string :number,       null: false # numero — string (handles "s/n", "150 A")
      t.string :complement                # complemento — only nullable field
      t.string :neighborhood, null: false # bairro
      t.string :city,         null: false # cidade
      t.string :state,        null: false # UF — 2-char Brazilian state code
      t.boolean :default,     null: false, default: false

      t.timestamps
    end

    add_index :addresses, [ :user_id, :default ]
  end
end
