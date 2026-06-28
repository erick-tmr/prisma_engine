require "test_helper"

module Admin
  class DashboardPresenterTest < ActiveSupport::TestCase
    setup { @presenter = DashboardPresenter.new }

    test "orders serialize every order, recent first, as raw values" do
      payload = @presenter.orders
      assert_equal Order.count, payload.size

      awaiting = orders(:awaiting)
      first = payload.first # recent_first → the 1h-old awaiting order leads
      assert_equal awaiting.number, first["n"]
      assert_equal awaiting.user.full_name, first["clientName"]
      assert_equal awaiting.shipment.city, first["city"]
      assert_equal awaiting.shipment.state, first["uf"]
      assert_equal awaiting.created_at.strftime("%Y-%m-%d"), first["date"]
      assert_equal "awaiting_payment", first["status"]
      assert_equal awaiting.total_cents, first["total"]
      assert_equal 1, first["items"]
    end

    test "clients exclude admins and derive situação plus order counts" do
      clients = @presenter.clients
      by_email = clients.index_by { |c| c["email"] }

      assert_includes by_email.keys, users(:confirmed).email
      refute_includes by_email.keys, users(:admin).email
      refute_includes by_email.keys, users(:unconfirmed_admin).email

      assert_equal "active",  by_email[users(:confirmed).email]["status"]
      assert_equal "pending", by_email[users(:unconfirmed).email]["status"]
      assert_equal "locked",  by_email[users(:locked).email]["status"]
      assert_equal 4, by_email[users(:confirmed).email]["orders"]
      assert_equal 0, by_email[users(:orderless).email]["orders"]
    end

    test "clients read city/UF from the default address, tolerating none" do
      by_email = @presenter.clients.index_by { |c| c["email"] }

      with_address = by_email[users(:locked).email]
      assert_equal "São Paulo", with_address["city"]
      assert_equal "SP", with_address["uf"]

      without_address = by_email[users(:confirmed).email]
      assert_nil without_address["city"]
      assert_nil without_address["uf"]
    end

    test "to_h carries the status, action and situação vocabularies from the locale" do
      payload = @presenter.to_h
      assert_equal Order::STATUSES, payload["statuses"]
      assert_equal I18n.t("account.orders.states.delivered.label"), payload["statusLabels"]["delivered"]
      assert_equal I18n.t("admin.dashboard.bulk_actions.cancel"), payload["actionLabels"]["cancel"]
      assert_equal I18n.t("admin.dashboard.situations.locked"), payload["situationLabels"]["locked"]
    end

    test "reports serialize each batch newest-first with operator, period and reprint url" do
      windowed = ProductionBatch.create!(operator: users(:admin), orders_count: 3,
                                         period_from: Date.new(2026, 6, 1), period_to: Date.new(2026, 6, 7),
                                         created_at: 2.hours.ago)
      open_ended = ProductionBatch.create!(operator: nil, orders_count: 5, created_at: 1.hour.ago)

      reports = @presenter.reports
      assert_equal 2, reports.size

      first = reports.first # recent_first → the open-ended batch leads
      assert_equal open_ended.id, first["id"]
      assert_equal I18n.t("admin.production_report.report.system"), first["operator"]
      assert_equal I18n.t("admin.production_report.report.all_periods"), first["period"]
      assert_equal 5, first["orders"]
      assert_equal "/admin/relatorio-producao/#{open_ended.id}", first["url"]

      windowed_row = reports.find { |row| row["id"] == windowed.id }
      assert_equal users(:admin).full_name, windowed_row["operator"]
      assert_equal "01/06/2026 a 07/06/2026", windowed_row["period"]
    end

    test "to_json round-trips the payload" do
      parsed = JSON.parse(@presenter.to_json)
      assert_equal @presenter.orders.size, parsed["orders"].size
      assert_equal DashboardPresenter::SITUATIONS, parsed["situationLabels"].keys
    end

    test "memoizes orders, clients and reports" do
      assert_same @presenter.orders, @presenter.orders
      assert_same @presenter.clients, @presenter.clients
      assert_same @presenter.reports, @presenter.reports
    end
  end
end
