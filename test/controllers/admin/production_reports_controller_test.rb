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

    test "the preview lists orders waiting for or already in production and hides the rest" do
      sign_in users(:admin)
      get admin_production_report_path

      assert_response :success
      assert_match orders(:confirmed_paid).number, response.body
      assert_match orders(:producing).number, response.body
      assert_no_match(/#{orders(:awaiting).number}/, response.body)
      assert_select "[data-pr-open]", text: /Enviar para produção e gerar/
      assert_select ".pr-modal__summary", text: /1 pedido passa para Em produção agora/
    end

    test "the preview offers a plain generate when every order is already in production" do
      sign_in users(:admin)
      orders(:confirmed_paid).transition_to!("in_production")
      get admin_production_report_path

      assert_select "[data-pr-open]", text: /Gerar relatório/
      assert_select ".pr-modal__summary", text: /Todos já estão Em produção/
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

    test "confirming sends the waiting orders to production and renders the sheet with the ones already there" do
      sign_in users(:admin)
      eligible = orders(:confirmed_paid)
      producing = orders(:producing)
      untouched = orders(:awaiting)
      with_variants = Order.create!(user: users(:confirmed), status: "payment_confirmed", subtotal_cents: 1_000, total_cents: 1_000)
      with_variants.order_items.create!(product: products(:yellow), name: "Pokemon - Gold", unit_price_cents: 1_000, quantity: 1,
                                        chosen_options: [ "Idioma: Inglês", "Cor da carcaça: Transparente" ])
      accessories_only = Order.create!(user: users(:confirmed), status: "payment_confirmed", subtotal_cents: 2_500, total_cents: 2_500)
      accessories_only.order_items.create!(product: products(:game_box), name: "Caixa", unit_price_cents: 2_500, quantity: 1, chosen_options: [])

      assert_no_difference -> { producing.status_changes.count } do
        post admin_production_report_path
      end

      assert_response :success
      assert eligible.reload.in_production?
      assert with_variants.reload.in_production?
      assert accessories_only.reload.in_production?, "an accessories-only order is eligible too"
      assert untouched.reload.awaiting_payment?

      change = eligible.status_changes.chronological.last
      assert_equal "in_production", change.to_status
      assert_equal users(:admin), change.actor

      assert_match eligible.number, response.body
      assert_match producing.number, response.body
      assert_no_match(/#{untouched.number}/, response.body)
      assert_select "a.pr-back[href=?]", admin_root_path
      assert_match users(:admin).full_name, response.body
      assert_select ".pr-item__flag", text: "🇺🇸"
      assert_select ".pr-item__variants", text: "Transparente"
    end

    test "the sheet prints every item of a mixed order" do
      sign_in users(:admin)
      mixed = Order.create!(user: users(:confirmed), status: "payment_confirmed", subtotal_cents: 1_000, total_cents: 1_000)
      mixed.order_items.create!(product: products(:metroid), name: "Metroid II", unit_price_cents: 1_000, quantity: 1, chosen_options: [])
      mixed.order_items.create!(product: products(:game_box), name: "Caixa do jogo", unit_price_cents: 2_500, quantity: 1, chosen_options: [])

      post admin_production_report_path

      assert_response :success
      assert_match "Metroid II", response.body
      assert_match "Caixa do jogo", response.body
    end

    test "the sheet shows the requested game and notes for made-to-order items" do
      sign_in users(:admin)
      pedido = Order.create!(user: users(:confirmed), status: "payment_confirmed", subtotal_cents: 38_000, total_cents: 38_000)
      pedido.order_items.create!(
        product: products(:pedido_game), name: "Pokémon Hacks (Pedidos)", unit_price_cents: 19_000, quantity: 1,
        chosen_options: [ "Idioma: Inglês" ], requested_game: "Pokémon Unbound", request_notes: "carcaça translúcida roxa"
      )
      pedido.order_items.create!(
        product: products(:pedido_game), name: "Game Boy Classic/Color (Pedidos)", unit_price_cents: 19_000, quantity: 1,
        chosen_options: [], requested_game: "Zelda Redux"
      )

      post admin_production_report_path

      assert_response :success
      assert_select ".pr-item__pedido-game", text: /Pokémon Unbound/
      assert_select ".pr-item__pedido-game", text: /Zelda Redux/
      assert_select ".pr-item__pedido-note", text: /carcaça translúcida roxa/
      assert_select ".pr-item__pedido-note", count: 1
    end

    test "the sheet shows the customer observation when the order has one" do
      sign_in users(:admin)
      noted = Order.create!(user: users(:confirmed), status: "payment_confirmed", subtotal_cents: 1_000, total_cents: 1_000,
                            observation: "Entregar após as 18h")
      noted.order_items.create!(product: products(:metroid), name: "Metroid II", unit_price_cents: 1_000, quantity: 1, chosen_options: [])

      post admin_production_report_path

      assert_response :success
      assert_select ".pr-order__note", text: /Observação:\s*Entregar após as 18h/
    end

    test "confirming with no eligible orders redirects with an alert" do
      sign_in users(:admin)

      post admin_production_report_path(de: "2020-01-01", ate: "2020-01-02")

      assert_redirected_to admin_production_report_path(de: "2020-01-01", ate: "2020-01-02")
      follow_redirect!
      assert_select ".pr-flash--alert"
    end

    test "re-confirming prints the same orders again without moving anything" do
      sign_in users(:admin)
      post admin_production_report_path
      first_sheet = css_select(".pr-order__number").map(&:text)

      assert_no_difference -> { OrderStatusChange.count } do
        post admin_production_report_path
      end

      assert_response :success
      assert_equal first_sheet, css_select(".pr-order__number").map(&:text)
    end
  end
end
