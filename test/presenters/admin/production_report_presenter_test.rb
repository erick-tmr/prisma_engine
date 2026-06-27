require "test_helper"

module Admin
  class ProductionReportPresenterTest < ActiveSupport::TestCase
    ELIGIBLE = ProductionReportPresenter::ELIGIBLE_STATUSES

    def make_order(status:, created_at: 1.day.ago, items: [ {} ])
      order = Order.create!(
        user: users(:confirmed), status: status,
        subtotal_cents: 1_000, total_cents: 1_000, created_at: created_at
      )
      items.each do |attrs|
        defaults = { product: products(:metroid), name: "Cartucho", unit_price_cents: 1_000, quantity: 1, chosen_options: [] }
        order.order_items.create!(defaults.merge(attrs))
      end
      order
    end

    test "every status it accepts is one the to_production move allows" do
      assert_equal Admin::OrderActions.lookup("to_production").from, ELIGIBLE
    end

    test "lists only production-eligible orders" do
      eligible = make_order(status: "payment_confirmed")
      ineligible = make_order(status: "awaiting_payment")

      numbers = ProductionReportPresenter.new.orders.map(&:number)
      assert_includes numbers, eligible.number
      assert_not_includes numbers, ineligible.number
      ProductionReportPresenter.new.orders.each { |order| assert_includes ELIGIBLE, order.status }
    end

    test "excludes orders that have no game items" do
      games = make_order(status: "payment_confirmed", items: [ { product: products(:metroid) } ])
      accessories_only = make_order(status: "payment_confirmed", items: [ { product: products(:game_box) } ])

      numbers = ProductionReportPresenter.new.orders.map(&:number)
      assert_includes numbers, games.number
      assert_not_includes numbers, accessories_only.number
    end

    test "a mixed order lists only its game items" do
      make_order(
        status: "payment_confirmed", created_at: Time.zone.local(2026, 1, 10, 9),
        items: [
          { product: products(:metroid), name: "Metroid II", chosen_options: [ "Idioma: Inglês" ] },
          { product: products(:game_box), name: "Caixa (estojo do jogo)" }
        ]
      )
      presenter = ProductionReportPresenter.new(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 31))
      names = presenter.rows.first.items.map(&:name)

      assert_equal [ "Metroid II" ], names
    end

    test "within a period it returns the eligible orders oldest-first" do
      older = make_order(status: "payment_confirmed", created_at: Time.zone.local(2026, 1, 10, 9))
      mid   = make_order(status: "awaiting_components", created_at: Time.zone.local(2026, 1, 12, 9))
      newer = make_order(status: "production_issue", created_at: Time.zone.local(2026, 1, 15, 9))
      make_order(status: "payment_confirmed", created_at: Time.zone.local(2025, 12, 31, 9)) # outside the window

      presenter = ProductionReportPresenter.new(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 31))

      assert_equal [ older.number, mid.number, newer.number ], presenter.orders.map(&:number)
      assert_equal 3, presenter.count
    end

    test "an open-ended period bounds only the given side" do
      make_order(status: "payment_confirmed", created_at: Time.zone.local(2026, 1, 10, 9))
      make_order(status: "payment_confirmed", created_at: Time.zone.local(2026, 3, 10, 9))

      from_dates = ProductionReportPresenter.new(from: Date.new(2026, 2, 1)).orders.map { |order| order.created_at.to_date.iso8601 }
      assert_includes from_dates, "2026-03-10"
      assert_not_includes from_dates, "2026-01-10"

      to_dates = ProductionReportPresenter.new(to: Date.new(2026, 2, 1)).orders.map { |order| order.created_at.to_date.iso8601 }
      assert_includes to_dates, "2026-01-10"
      assert_not_includes to_dates, "2026-03-10"
    end

    test "rows carry the sequence, customer, number, date and formatted items" do
      make_order(
        status: "payment_confirmed", created_at: Time.zone.local(2026, 1, 10, 9),
        items: [ { name: "Pokemon - Gold (Patch RTC)", quantity: 2,
                   chosen_options: [ "Idioma: Inglês", "Caixa: Com Caixa" ] } ]
      )
      presenter = ProductionReportPresenter.new(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 31))
      row = presenter.rows.first

      assert_equal 1, row.seq
      assert_equal users(:confirmed).full_name, row.customer
      assert_match(/\APG-/, row.number)
      assert_equal "10/01/2026", row.placed_on
      assert_equal 2, row.items.first.quantity
      assert_equal "Pokemon - Gold (Patch RTC)", row.items.first.name
      assert_equal "Inglês · Com Caixa", row.items.first.variants
    end

    test "variant summary strips the group prefix and tolerates plain or empty options" do
      make_order(
        status: "payment_confirmed", created_at: Time.zone.local(2026, 1, 10, 9),
        items: [ { chosen_options: [ "ROM: Crystal", "Edição limitada" ] }, { chosen_options: [] } ]
      )
      presenter = ProductionReportPresenter.new(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 31))
      items = presenter.rows.first.items

      assert_equal "Crystal · Edição limitada", items.first.variants
      assert_equal "", items.second.variants
    end

    test "period clause and iso readers reflect whether a window was given" do
      open_ended = ProductionReportPresenter.new
      assert_equal I18n.t("admin.production_report.period_all"), open_ended.period_clause
      assert_nil open_ended.from_iso
      assert_nil open_ended.to_iso

      windowed = ProductionReportPresenter.new(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 31))
      assert_equal "do período 01/01/2026 a 31/01/2026", windowed.period_clause
      assert_equal "2026-01-01", windowed.from_iso
      assert_equal "2026-01-31", windowed.to_iso
    end
  end
end
