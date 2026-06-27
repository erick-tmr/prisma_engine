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

    test "confirming records a batch, sends the eligible orders to production and redirects to the sheet" do
      sign_in users(:admin)
      eligible = orders(:confirmed_paid)
      untouched = orders(:awaiting)
      with_variants = Order.create!(user: users(:confirmed), status: "payment_confirmed", subtotal_cents: 1_000, total_cents: 1_000)
      with_variants.order_items.create!(product: products(:yellow), name: "Pokemon - Gold", unit_price_cents: 1_000, quantity: 1,
                                        chosen_options: [ "Idioma: Inglês", "Cor da carcaça: Transparente" ])
      accessories_only = Order.create!(user: users(:confirmed), status: "payment_confirmed", subtotal_cents: 2_500, total_cents: 2_500)
      accessories_only.order_items.create!(product: products(:game_box), name: "Caixa", unit_price_cents: 2_500, quantity: 1, chosen_options: [])

      assert_difference -> { ProductionBatch.count }, 1 do
        post admin_production_report_path
      end

      batch = ProductionBatch.order(:id).last
      assert_redirected_to admin_production_report_batch_path(batch)
      assert_equal users(:admin), batch.operator
      assert_equal 2, batch.orders_count
      assert eligible.reload.in_production?
      assert_equal batch, eligible.production_batch
      assert with_variants.reload.in_production?
      assert untouched.reload.awaiting_payment?
      assert accessories_only.reload.payment_confirmed?, "an accessories-only order must not be sent to production"
      assert_nil accessories_only.production_batch

      change = eligible.status_changes.chronological.last
      assert_equal "in_production", change.to_status
      assert_equal users(:admin), change.actor

      follow_redirect!
      assert_response :success
      assert_select ".pr-order"
      assert_select ".pr-item__variants", text: "Inglês · Transparente"
    end

    test "the sheet prints only the game items of a mixed order" do
      sign_in users(:admin)
      mixed = Order.create!(user: users(:confirmed), status: "payment_confirmed", subtotal_cents: 1_000, total_cents: 1_000)
      mixed.order_items.create!(product: products(:metroid), name: "Metroid II", unit_price_cents: 1_000, quantity: 1, chosen_options: [])
      mixed.order_items.create!(product: products(:game_box), name: "Caixa do jogo", unit_price_cents: 2_500, quantity: 1, chosen_options: [])

      post admin_production_report_path
      follow_redirect!

      assert_response :success
      assert_match "Metroid II", response.body
      assert_no_match(/Caixa do jogo/, response.body)
    end

    test "show reprints a stored batch from its frozen orders" do
      sign_in users(:admin)
      order = orders(:confirmed_paid)
      post admin_production_report_path
      batch = ProductionBatch.order(:id).last

      get admin_production_report_batch_path(batch)

      assert_response :success
      assert_select ".pr-order"
      assert_match order.number, response.body
      assert_match "Lote ##{batch.id}", response.body
    end

    test "confirming with no eligible orders redirects with an alert and records no batch" do
      sign_in users(:admin)

      assert_no_difference -> { ProductionBatch.count } do
        post admin_production_report_path(de: "2020-01-01", ate: "2020-01-02")
      end

      assert_redirected_to admin_production_report_path(de: "2020-01-01", ate: "2020-01-02")
      follow_redirect!
      assert_select ".pr-flash--alert"
    end

    test "re-confirming is a no-op once the batch already moved" do
      sign_in users(:admin)

      post admin_production_report_path
      assert_response :redirect

      post admin_production_report_path # nothing eligible left in the fixtures
      assert_redirected_to admin_production_report_path
      follow_redirect!
      assert_select ".pr-flash--alert"
    end
  end
end
