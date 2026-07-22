require "test_helper"

module Admin
  class ProductionReportPresenterTest < ActiveSupport::TestCase
    def order_with(items, created_at: Time.zone.local(2026, 1, 10, 9))
      order = Order.create!(
        user: users(:confirmed), status: "in_production",
        subtotal_cents: 1_000, total_cents: 1_000, created_at: created_at
      )
      items.each do |attrs|
        defaults = { product: products(:metroid), name: "Cartucho", unit_price_cents: 1_000, quantity: 1, chosen_options: [] }
        order.order_items.create!(defaults.merge(attrs))
      end
      order
    end

    test "rows carry the sequence, customer, number, date and formatted game items" do
      order = order_with([ { name: "Pokemon - Gold (Patch RTC)", quantity: 2, chosen_options: [ "Idioma: Inglês", "Caixa: Com Caixa" ] } ])
      presenter = ProductionReportPresenter.new(orders: [ order ])
      row = presenter.rows.first

      assert_equal 1, presenter.count
      assert_equal 1, row.seq
      assert_equal users(:confirmed).full_name, row.customer
      assert_match(/\APG-/, row.number)
      assert_equal "10/01/2026", row.placed_on
      assert_equal 2, row.items.first.quantity
      assert_equal "Pokemon - Gold (Patch RTC)", row.items.first.name
      assert_equal [ "Inglês", "Com Caixa" ], row.items.first.variants
    end

    test "rows list every item in creation order, stripping the group prefix and tolerating plain options" do
      order = order_with([
        { product: products(:metroid), name: "Metroid II", chosen_options: [ "ROM: Crystal", "Edição limitada" ] },
        { product: products(:game_box), name: "Caixa (estojo do jogo)" }
      ])
      items = ProductionReportPresenter.new(orders: [ order ]).rows.first.items

      assert_equal [ "Metroid II", "Caixa (estojo do jogo)" ], items.map(&:name)
      assert_equal [ "Crystal", "Edição limitada" ], items.first.variants
    end

    test "an item with no chosen options renders no variant values" do
      order = order_with([ { chosen_options: [] } ])
      assert_equal [], ProductionReportPresenter.new(orders: [ order ]).rows.first.items.first.variants
    end

    test "items carry the made-to-order requested game and notes" do
      order = order_with([
        { name: "Pokémon Hacks (Pedidos)", requested_game: "Pokémon Unbound", request_notes: "carcaça roxa" },
        { name: "Metroid II" }
      ])
      items = ProductionReportPresenter.new(orders: [ order ]).rows.first.items

      pedido = items.find { |item| item.name == "Pokémon Hacks (Pedidos)" }
      assert_equal "Pokémon Unbound", pedido.requested_game
      assert_equal "carcaça roxa", pedido.request_notes

      plain = items.find { |item| item.name == "Metroid II" }
      assert_nil plain.requested_game
      assert_nil plain.request_notes
    end

    test "rows carry the customer observation" do
      order = order_with([ { chosen_options: [] } ])
      order.update!(observation: "Sem etiqueta repro")
      row = ProductionReportPresenter.new(orders: [ order ]).rows.first
      assert_equal "Sem etiqueta repro", row.observation
    end

    test "for_batch reprints the batch's own orders, every item, with its stored period" do
      order = order_with([ { product: products(:metroid), name: "Metroid II" }, { product: products(:game_box), name: "Caixa" } ])
      batch = ProductionBatch.create!(period_from: Date.new(2026, 1, 1), period_to: Date.new(2026, 1, 31), orders_count: 1)
      order.update!(production_batch: batch)

      presenter = ProductionReportPresenter.for_batch(batch)

      assert_equal [ order.number ], presenter.orders.map(&:number)
      assert_equal [ "Metroid II", "Caixa" ], presenter.rows.first.items.map(&:name)
      assert_equal "do período 01/01/2026 a 31/01/2026", presenter.period_clause
    end

    test "period clause and iso readers reflect whether a window was given" do
      open_ended = ProductionReportPresenter.new(orders: [])
      assert_equal I18n.t("admin.production_report.period_all"), open_ended.period_clause
      assert_nil open_ended.from_iso
      assert_nil open_ended.to_iso

      windowed = ProductionReportPresenter.new(orders: [], from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 31))
      assert_equal "do período 01/01/2026 a 31/01/2026", windowed.period_clause
      assert_equal "2026-01-01", windowed.from_iso
      assert_equal "2026-01-31", windowed.to_iso
    end
  end
end
