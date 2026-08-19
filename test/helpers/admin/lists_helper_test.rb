require "test_helper"

module Admin
  class ListsHelperTest < ActionView::TestCase
    include Admin::ListsHelper

    setup { self.request = ActionDispatch::TestRequest.create.tap { |r| r.path = "/admin" } }

    test "list_path keeps the bare path when nothing is set" do
      assert_equal "/admin", list_path({})
      assert_equal "/admin", list_path({ q: nil, sort: "" })
    end

    test "list_path merges overrides and drops what they blank out" do
      assert_equal "/admin?q=ana", list_path({ q: "ana" })
      assert_equal "/admin?q=ana&sort=total", list_path({ q: "ana" }, sort: "total")
      assert_equal "/admin?q=ana", list_path({ q: "ana", page: 3 }, page: nil)
    end

    test "page_path leaves the first page unnumbered" do
      assert_equal "/admin?q=ana", page_path({ q: "ana" }, 1)
      assert_equal "/admin?page=2&q=ana", page_path({ q: "ana" }, 2)
    end

    test "page_range reads as a bare count while everything fits on one page" do
      assert_equal "<b>20</b> produtos", page_range(page_for(20), "produto", "produtos")
      assert_equal "<b>1</b> produto", page_range(page_for(1), "produto", "produtos")
    end

    test "page_range spells out the window once there is more than one page" do
      assert_equal "<b>1–30</b> de <b>31</b> produtos",
                   page_range(page_for(31), "produto", "produtos")
    end

    test "page_range follows the list's own page size, not the default one" do
      assert_equal "<b>1–8</b> de <b>20</b> pedidos",
                   page_range(page_for(20, per: 8), "pedido", "pedidos")
    end

    test "drawer_title names the state the question is actually in" do
      assert_equal "Pergunta em spam", drawer_title(questions(:spam_yellow))
      assert_equal "Pergunta ##{questions(:answered_yellow).id}", drawer_title(questions(:answered_yellow))
      assert_equal "Responder pergunta", drawer_title(questions(:awaiting_yellow))
    end

    test "sort_header links to the other direction and marks the active column" do
      inactive = sort_header({}, key: "total", label: "Total", sort: "date", dir: "desc")
      assert_includes inactive, "sortable"
      assert_not_includes inactive, "sorted"
      assert_includes inactive, "sort=total"
      assert_includes inactive, "dir=desc"

      active = sort_header({}, key: "date", label: "Data", sort: "date", dir: "desc")
      assert_includes active, "sorted"
      assert_includes active, "▼"
      assert_includes active, "dir=asc"

      flipped = sort_header({}, key: "date", label: "Data", sort: "date", dir: "asc")
      assert_includes flipped, "▲"
      assert_includes flipped, "dir=desc"
    end

    test "sort_header honours a column's own default direction and numeric alignment" do
      assert_includes sort_header({}, key: "client", label: "Cliente", sort: "date", dir: "desc", default_dir: "asc"), "dir=asc"
      assert_includes sort_header({}, key: "total", label: "Total", sort: "date", dir: "desc", extra_class: "num"), "num"
    end

    test "sort_header drops the page, so a re-sort starts at the top" do
      assert_not_includes sort_header({ page: 4 }, key: "total", label: "Total", sort: "date", dir: "desc"), "page"
    end

    test "avatar_tint and format_phone reuse the shared implementations" do
      assert_equal AvatarTint.index_for("Ana Cardoso"), avatar_tint("Ana Cardoso")
      assert_equal "(11) 98876-5521", format_phone("11988765521")
    end

    test "period_label shows one date or a range" do
      from = Date.new(2026, 6, 10)
      assert_equal "10 jun 2026", period_label(from, nil)
      assert_equal "10 jun 2026 – 12 jun 2026", period_label(from, Date.new(2026, 6, 12))
    end

    test "status_trigger_label counts what is ticked" do
      assert_equal I18n.t("admin.dashboard.orders.filters.status_all"), status_trigger_label([])
      assert_equal I18n.t("account.orders.states.shipped.label"), status_trigger_label([ "shipped" ])
      assert_equal I18n.t("admin.lists.statuses_selected"), status_trigger_label(%w[shipped delivered])
    end

    test "the expired-label filter names itself, since it is not an Order status" do
      expected = I18n.t("admin.dashboard.orders.filters.label_expired")

      assert_equal expected, status_option_label("label_expired")
      assert_equal expected, status_trigger_label([ "label_expired" ])
      assert_equal I18n.t("account.orders.states.shipped.label"), status_option_label("shipped")
    end

    test "batch_period covers an open, half-open and closed range" do
      batch = ProductionBatch.new
      assert_equal I18n.t("admin.production_report.report.all_periods"), batch_period(batch)

      batch.period_from = Date.new(2026, 6, 1)
      assert_equal I18n.l(Date.new(2026, 6, 1)), batch_period(batch)

      batch.period_to = Date.new(2026, 6, 30)
      assert_equal "01/06/2026 a 30/06/2026", batch_period(batch)
    end

    private

    def page_for(total, per: Admin::Page::PER)
      Admin::Page.new(Product.limit(0), 1, per: per).tap do |page|
        page.instance_variable_set(:@total, total)
      end
    end
  end
end
