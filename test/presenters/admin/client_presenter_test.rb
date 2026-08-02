require "test_helper"

module Admin
  class ClientPresenterTest < ActiveSupport::TestCase
    test "the situation mirrors the SQL the clients list sorts on" do
      assert_equal "locked", ClientPresenter.new(users(:locked)).situation
      assert_equal "pending", ClientPresenter.new(users(:unconfirmed)).situation
      assert_equal "active", ClientPresenter.new(users(:confirmed)).situation
    end

    test "the reference pads the id to four digits" do
      client = users(:buyer)
      assert_equal format("%04d", client.id), ClientPresenter.new(client).reference
    end

    test "spend counts paid orders only, and cancellations are called out separately" do
      client = users(:orderless)
      client.orders.create!(subtotal_cents: 10_000, total_cents: 12_000, status: "delivered")
      client.orders.create!(subtotal_cents: 20_000, total_cents: 24_000, status: "shipped")
      client.orders.create!(subtotal_cents: 30_000, total_cents: 30_000, status: "awaiting_payment")
      client.orders.create!(subtotal_cents: 40_000, total_cents: 40_000, status: "cancelled")
      client.orders.create!(subtotal_cents: 50_000, total_cents: 50_000).update_column(:status, "merged")
      stats = ClientPresenter.new(client).stats

      assert_equal 5, stats.orders
      assert_equal 1, stats.cancelled
      assert_equal 2, stats.paid
      assert_equal 36_000, stats.spent_cents
      assert_equal 18_000, stats.average_ticket_cents
    end

    test "a client with nothing paid has no ticket to average" do
      stats = ClientPresenter.new(users(:orderless)).stats

      assert_equal 0, stats.spent_cents
      assert_nil stats.average_ticket_cents
      assert_nil stats.last_order
    end

    test "the last order is the most recent one" do
      client = users(:confirmed)
      newest = client.orders.recent_first.first

      assert_equal newest, ClientPresenter.new(client).stats.last_order
    end

    test "the ban state names the four panels the ledger renders" do
      served = client_with_strikes(1, name: "Reincidente", cpf: SPARE_CPFS[0], last_strike_at: 30.days.ago)
      permanent = client_with_strikes(3, name: "Banido", cpf: SPARE_CPFS[1])

      assert_equal "clear", ClientPresenter.new(users(:orderless)).ban_state
      assert_equal "banned", ClientPresenter.new(users(:buyer)).ban_state
      assert_equal "served", ClientPresenter.new(served).ban_state
      assert_equal "perma", ClientPresenter.new(permanent).ban_state
    end

    test "rungs light up as the strikes land" do
      client = client_with_strikes(1, name: "Reincidente", cpf: SPARE_CPFS[0], last_strike_at: 30.days.ago)
      presenter = ClientPresenter.new(client)
      states = presenter.ban.ladder.map { |rung| presenter.rung_state(rung) }

      assert_equal [ "spent current", "next", "upcoming" ], states
    end

    test "every rung is spent once the ban is permanent" do
      presenter = ClientPresenter.new(client_with_strikes(3, name: "Banido", cpf: SPARE_CPFS[0]))
      states = presenter.ban.ladder.map { |rung| presenter.rung_state(rung) }

      assert_equal [ "spent", "spent", "spent current" ], states
    end

    test "strikes come back oldest first, with the question and product loaded" do
      presenter = ClientPresenter.new(client_with_strikes(3, name: "Banido", cpf: SPARE_CPFS[0]))
      issued = presenter.strikes.map(&:created_at)

      assert_equal issued.sort, issued
      assert_equal 3, presenter.strikes.size
    end

    test "addresses put the default one first" do
      presenter = ClientPresenter.new(users(:locked))

      assert_equal [ addresses(:locked_home) ], presenter.addresses.to_a
    end
  end
end
