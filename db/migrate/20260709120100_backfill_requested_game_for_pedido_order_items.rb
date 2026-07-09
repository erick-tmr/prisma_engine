class BackfillRequestedGameForPedidoOrderItems < ActiveRecord::Migration[8.1]
  BACKFILL_LABEL = "Pedido registrado antes do formulário".freeze
  PEDIDO_CATEGORY_SLUG = "pedidos-de-jogos".freeze

  def up
    execute(<<~SQL)
      UPDATE order_items oi
      SET requested_game = #{quote(BACKFILL_LABEL)}
      FROM products p
      JOIN categories c ON c.id = p.category_id
      WHERE oi.product_id = p.id
        AND c.slug = #{quote(PEDIDO_CATEGORY_SLUG)}
        AND (oi.requested_game IS NULL OR oi.requested_game = '')
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
