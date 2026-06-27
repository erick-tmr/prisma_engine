require "test_helper"

module Admin
  class ProductionReportsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    test "non-admins are sent to the backoffice login" do
      get admin_production_report_path
      assert_redirected_to admin_login_path

      post admin_production_report_path
      assert_redirected_to admin_login_path
    end

    test "the preview lists production-eligible orders and hides the rest" do
      sign_in users(:admin)
      get admin_production_report_path

      assert_response :success
      assert_match orders(:confirmed_paid).number, response.body # payment_confirmed → eligible
      assert_no_match(/#{orders(:awaiting).number}/, response.body)   # awaiting_payment → hidden
      assert_no_match(/#{orders(:producing).number}/, response.body)  # already in_production → hidden
      assert_select "[data-pr-open]"
    end

    test "the preview narrows to the selected period and shows the empty state" do
      sign_in users(:admin)
      get admin_production_report_path(de: "2020-01-01", ate: "2020-01-02")

      assert_response :success
      assert_select ".pr-empty"
      assert_no_match orders(:confirmed_paid).number, response.body
    end

    test "a malformed period param is ignored rather than blowing up" do
      sign_in users(:admin)
      get admin_production_report_path(de: "not-a-date")

      assert_response :success
      assert_match orders(:confirmed_paid).number, response.body
    end

    test "confirming sends the eligible batch to production and renders the sheet" do
      sign_in users(:admin)
      eligible = orders(:confirmed_paid)
      untouched = orders(:awaiting)
      with_variants = Order.create!(user: users(:confirmed), status: "payment_confirmed", subtotal_cents: 1_000, total_cents: 1_000)
      with_variants.order_items.create!(name: "Pokemon - Gold", unit_price_cents: 1_000, quantity: 1,
                                        chosen_options: [ "Idioma: Inglês", "Caixa: Com Caixa" ])

      post admin_production_report_path

      assert_response :success
      assert_select ".pr-order"
      assert_select ".pr-item__variants", text: "Inglês · Com Caixa"
      assert eligible.reload.in_production?
      assert with_variants.reload.in_production?
      assert untouched.reload.awaiting_payment?

      change = eligible.status_changes.chronological.last
      assert_equal "in_production", change.to_status
      assert_equal users(:admin), change.actor
    end

    test "confirming with no eligible orders redirects with an alert" do
      sign_in users(:admin)

      post admin_production_report_path(de: "2020-01-01", ate: "2020-01-02")

      assert_redirected_to admin_production_report_path(de: "2020-01-01", ate: "2020-01-02")
      follow_redirect!
      assert_select ".pr-flash--alert"
    end

    test "re-confirming is a no-op once the batch already moved" do
      sign_in users(:admin)

      post admin_production_report_path
      assert_response :success

      post admin_production_report_path # nothing eligible left in the fixtures
      assert_redirected_to admin_production_report_path
      follow_redirect!
      assert_select ".pr-flash--alert"
    end
  end
end
