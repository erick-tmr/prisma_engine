require "test_helper"

module Admin
  class ListsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    LISTS = { orders: "/admin", clients: "/admin/clientes", reports: "/admin/relatorios" }.freeze

    test "signed-out visitors are sent to the backoffice login" do
      LISTS.each_value do |path|
        get path
        assert_redirected_to admin_login_path
      end
    end

    test "signed-in non-admins are sent to the backoffice login" do
      sign_in users(:confirmed)
      LISTS.each_value do |path|
        get path
        assert_redirected_to admin_login_path
      end
    end

    test "each list is its own page carrying the shared backoffice shell" do
      sign_in users(:admin)

      LISTS.each do |name, path|
        get path
        assert_response :success
        assert_select ".app[data-list=?]", name.to_s
        assert_select ".sb-link[href=?]", admin_clients_path
        assert_select "script[type=importmap]", count: 1
      end
    end

    test "the sidebar counts every collection on every list" do
      sign_in users(:admin)
      get admin_root_path

      assert_select ".sb-link .count", text: Order.count.to_s
      assert_select ".sb-link .count", text: User.where(admin: false).count.to_s
      assert_select ".sb-user .nm", text: users(:admin).full_name
    end

    test "the orders list shows the paid total over the whole table" do
      sign_in users(:admin)
      get admin_root_path

      expected = Admin::OrdersController.helpers.format_brl(Order.paid.sum(:total_cents))
      assert_select ".result-count--paid", text: "Total pago: #{expected}"
    end

    test "a fetch request returns just the results, without the page shell" do
      sign_in users(:admin)
      get admin_root_path, headers: { "X-Requested-With" => "fetch" }

      assert_response :success
      assert_no_match(/<html/, response.body)
      assert_select "[data-part=count]", count: 1
      assert_select "[data-part=table]", count: 1
      assert_select ".sidebar", count: 0
    end

    test "orders keep merged consolidations out until the status is ticked" do
      sign_in users(:admin)
      merged = orders(:awaiting).user.orders.create!(subtotal_cents: 100, total_cents: 100)
      merged.update_column(:status, "merged")

      get admin_root_path
      assert_select "tr[data-order=?]", merged.number, count: 0

      get admin_root_path, params: { status: [ "merged" ] }
      assert_select "tr[data-order=?]", merged.number, count: 1
    end

    test "orders filter by client name and by order number" do
      sign_in users(:admin)
      order = orders(:confirmed_paid)

      get admin_root_path, params: { q: order.number.downcase }
      assert_select "tr[data-order]", count: 1
      assert_select "tr[data-order=?]", order.number

      get admin_root_path, params: { q: order.user.full_name.split.first }
      assert_select "tr[data-order]", minimum: 1
    end

    test "orders carry the active period into the production report link" do
      sign_in users(:admin)
      get admin_root_path, params: { de: "2026-06-01", ate: "2026-06-30" }

      assert_select "#gen-production[href=?]",
                    "#{admin_production_report_path}?ate=2026-06-30&de=2026-06-01"
    end

    test "hostile or nonsense params fall back to the defaults instead of raising" do
      sign_in users(:admin)

      get admin_root_path, params: { page: "0", sort: "total; DROP TABLE orders", dir: "sideways",
                                     status: [ "not_a_status" ], de: "not-a-date" }
      assert_response :success
      assert_select "[data-part=table]"

      get admin_root_path, params: { page: "99999" }
      assert_response :success
    end

    test "a list longer than one page renders numbered links that carry the filters" do
      sign_in users(:admin)
      31.times do |i|
        Product.create!(category: categories(:gb_color), name: "Filler #{i}",
                        price_cents: 1_000, weight_grams: 20, published: true)
      end

      get admin_products_path, params: { q: "filler" }
      assert_select "tr[data-row]", count: 30
      assert_select ".tbl-foot .foot-range", text: /1–30 de 31 produtos/
      assert_select ".tbl-foot a.pg[href=?]", "#{admin_products_path}?page=2&q=filler"

      get admin_products_path, params: { q: "filler", page: 2 }
      assert_select "tr[data-row]", count: 1
      assert_select ".tbl-foot a.pg.on", text: "2"
      assert_select ".tbl-foot .pg-nav.is-disabled", count: 1
    end

    test "clients and catalog accept their own filters" do
      sign_in users(:admin)

      get admin_clients_path, params: { q: users(:confirmed).full_name, sort: "orders", dir: "desc" }
      assert_response :success
      assert_select "tr[data-client]", minimum: 1

      get admin_products_path, params: { status: "gotm" }
      assert_response :success
      assert_select "tr[data-row]", count: Product.joins(:game_of_the_month_products).distinct.count
    end
  end
end
