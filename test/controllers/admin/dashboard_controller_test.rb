require "test_helper"

module Admin
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    test "signed-out visitors are sent to the backoffice login" do
      get admin_root_path
      assert_redirected_to admin_login_path
    end

    test "signed-in non-admins are sent to the backoffice login" do
      sign_in users(:confirmed)
      get admin_root_path
      assert_redirected_to admin_login_path
    end

    test "signed-in admins see the dashboard" do
      sign_in users(:admin)
      get admin_root_path
      assert_response :success
      assert_select "h1"
    end

    test "the dashboard embeds the data island, real counts and the operator name" do
      sign_in users(:admin)
      get admin_root_path

      assert_response :success
      assert_select ".app[data-dashboard]"
      assert_select ".sb-link[data-view=orders] .count", text: Order.count.to_s
      assert_select ".sb-link[data-view=clients] .count", text: User.where(admin: false).count.to_s
      assert_select ".sb-user .nm", text: users(:admin).full_name
      assert_includes response.body, orders(:awaiting).number
    end

    test "every table gets a pagination mount and the importmap that resolves the pager" do
      sign_in users(:admin)
      get admin_root_path

      assert_select "#orders-foot.tbl-foot"
      assert_select "#clients-foot.tbl-foot"
      assert_select "#reports-foot.tbl-foot"
      assert_select "script[type=importmap]", count: 1
      assert_match %r{"backoffice/pager":}, response.body
    end

    test "the orders panel shows the paid total over the whole table" do
      sign_in users(:admin)
      get admin_root_path

      expected = Admin::DashboardController.helpers.format_brl(Order.paid.sum(:total_cents))
      assert_select ".result-count--paid", text: "Total pago: #{expected}"
      assert_not_equal Order.sum(:total_cents), Order.paid.sum(:total_cents)
    end

    test "each sidebar tab has its own dedicated path that renders the dashboard" do
      sign_in users(:admin)

      get admin_clients_path
      assert_response :success
      assert_select ".app[data-dashboard]"

      get admin_reports_path
      assert_response :success
      assert_select ".app[data-dashboard]"

      assert_select "aside.sidebar a.sb-link[href=?]", admin_clients_path
      assert_select "aside.sidebar a.sb-link[href=?]", admin_reports_path
    end
  end
end
