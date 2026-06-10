require "test_helper"

class CartTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "GET /carrinho renders the empty state when no items are in the cookie" do
    get "/carrinho"
    assert_response :success
    assert_match(/Seu carrinho está vazio/, response.body)
    assert_select ".cart-empty-art i.bi-controller"
    assert_select ".cart-empty a", text: /Ver catálogo/
    # WhatsApp button is gone from the empty state (the layout's nav-strip social
    # icon doesn't count; scope the assertion to .cart-empty).
    assert_select ".cart-empty a[href*='wa.me']", count: 0
    # Mobile bar isn't rendered when the cart is empty
    assert_select "[data-mobile-bar]", count: 0
    assert_select "[data-cart-count]", text: "0"
  end

  test "mobile sticky bar is rendered with the current subtotal when the cart has items" do
    post cart_items_path, params: {
      product_id: products(:yellow).id, quantity: 2,
      option_ids: [ product_options(:yellow_caixa_com).id ]
    }
    get "/carrinho"
    # 19000 unit (18000 + 1000 delta) * 2 = 38000
    assert_select "[data-mobile-bar] [data-mb-total]", text: /R\$ 380\.00/
  end

  test "adding a product writes a signed cart cookie and bumps the header counter" do
    post cart_items_path, params: {
      product_id: products(:yellow).id,
      quantity: 2,
      option_ids: [ product_options(:yellow_idioma_en).id, product_options(:yellow_caixa_sem).id ]
    }
    assert_redirected_to "/carrinho"
    follow_redirect!
    assert_select "[data-head-count]", text: /2 itens/
    assert_select "[data-list-count]", text: /1 produto/
    assert_select "[data-cart-count]", text: "2"
    assert_select ".cart-item-title", text: /Pokemon Yellow Version/
  end

  test "adding the same product+options merges into one line" do
    post cart_items_path, params: { product_id: products(:yellow).id, quantity: 1, option_ids: [ product_options(:yellow_idioma_pt).id ] }
    post cart_items_path, params: { product_id: products(:yellow).id, quantity: 3, option_ids: [ product_options(:yellow_idioma_pt).id ] }
    get "/carrinho"
    assert_select "[data-head-count]", text: /4 itens/
    assert_select "[data-list-count]", text: /1 produto/
  end

  test "updating quantity via PATCH clamps and persists" do
    post cart_items_path, params: { product_id: products(:yellow).id, quantity: 1, option_ids: [] }
    line_id = Cart::Bag.from_cookie(JSON.parse(request.cookie_jar.signed[:cart].to_json)).items.first["id"]

    patch cart_item_path(line_id), params: { quantity: 200 }
    follow_redirect!
    assert_select "[data-head-count]", text: /99 itens/
  end

  test "updating options swaps the chosen option but keeps the same line id" do
    post cart_items_path, params: {
      product_id: products(:yellow).id, quantity: 1,
      option_ids: [ product_options(:yellow_idioma_pt).id ]
    }
    line_id = Cart::Bag.from_cookie(JSON.parse(request.cookie_jar.signed[:cart].to_json)).items.first["id"]

    patch cart_item_path(line_id), params: { option_ids: [ product_options(:yellow_idioma_en).id ] }
    follow_redirect!

    bag = Cart::Bag.from_cookie(JSON.parse(request.cookie_jar.signed[:cart].to_json))
    assert_equal line_id, bag.items.first["id"]
    assert_equal [ product_options(:yellow_idioma_en).id ], bag.items.first["o"]
  end

  test "PATCH with an unknown line id is a tolerant no-op" do
    post cart_items_path, params: { product_id: products(:yellow).id, quantity: 1, option_ids: [] }
    patch cart_item_path("does-not-exist"), params: { option_ids: [ product_options(:yellow_idioma_en).id ] }
    assert_redirected_to "/carrinho"
  end

  test "DELETE removes a line" do
    post cart_items_path, params: { product_id: products(:yellow).id, quantity: 1, option_ids: [] }
    line_id = Cart::Bag.from_cookie(JSON.parse(request.cookie_jar.signed[:cart].to_json)).items.first["id"]

    delete cart_item_path(line_id)
    follow_redirect!
    assert_match(/Seu carrinho está vazio/, response.body)
  end

  test "Jogo do Mês chip renders for the current GOTM product, not for others" do
    # The fixture pairs current_month with the yellow product, so it is the GOTM.
    post cart_items_path, params: { product_id: products(:yellow).id, quantity: 1, option_ids: [] }
    post cart_items_path, params: { product_id: products(:metroid).id, quantity: 1, option_ids: [] }
    get "/carrinho"
    assert_select ".cart-item.is-gotm .chip-edicao", text: /Jogo do Mês/
    # Metroid is not in the current GOTM
    assert_select ".cart-item.is-gotm", count: 1
  end

  test "no Jogo do Mês chip when there is no GOTM set for the current month" do
    GameOfTheMonth.destroy_all
    post cart_items_path, params: { product_id: products(:yellow).id, quantity: 1, option_ids: [] }
    get "/carrinho"
    assert_response :success
    assert_select ".chip-edicao", count: 0
  end

  test "finalize bounces a guest to login and remembers the identificacao return path" do
    post cart_finalize_path
    assert_redirected_to new_user_session_path
    assert_equal identificacao_path, session["user_return_to"]
  end

  test "finalize sends a signed-in user straight to identificacao" do
    sign_in users(:confirmed)
    post cart_finalize_path
    assert_redirected_to identificacao_path
  end

  test "subtotal reflects the option delta on the line" do
    post cart_items_path, params: {
      product_id: products(:yellow).id, quantity: 2,
      option_ids: [ product_options(:yellow_caixa_com).id ]
    }
    get "/carrinho"
    # 19000 unit * 2 = 38000
    assert_select "[data-subtotal]", text: /R\$ 380\.00/
    assert_select "[data-total]",    text: /R\$ 380\.00/
  end

  test "lines whose product was deleted are silently dropped from the cookie" do
    post cart_items_path, params: { product_id: products(:yellow).id, quantity: 1, option_ids: [] }
    Product.where(id: products(:yellow).id).update_all(published: false)
    get "/carrinho"
    assert_match(/Um item do seu carrinho não está mais disponível/, response.body)
    assert_select "[data-cart-count]", text: "0"
  end
end
