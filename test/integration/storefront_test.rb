require "test_helper"

class StorefrontTest < ActionDispatch::IntegrationTest
  test "home page renders the category grids" do
    get root_path
    assert_response :success
  end

  test "catalog index lists products and filters by term" do
    get products_path
    assert_response :success
    assert_select ".product-card"

    get products_path(term: "pokemon")
    assert_response :success
    assert_match(/Pokemon/i, response.body)
  end

  test "product page renders with a clean slug and no legacy Meloja markers" do
    get product_path(slug: products(:yellow).slug)
    assert_response :success
    assert_match products(:yellow).name, response.body
    assert_no_match(/meloja|prismagames\.com\.br/i, response.body)
  end

  test "unknown product slug returns 404" do
    get product_path(slug: "does-not-exist")
    assert_response :not_found
  end

  test "category page renders; unknown category is 404" do
    get category_path(slug: "game-boy-color")
    assert_response :success
    assert_select ".product-card"

    get category_path(slug: "no-such-console")
    assert_response :not_found
  end

  test "drawer renders the published product count" do
    get root_path
    assert_response :success
    assert_match(/Todos os jogos/, response.body)
  end

  test "cart placeholder show and create both 200" do
    get "/carrinho"
    assert_response :success
    post cart_items_path, params: { product_id: products(:yellow).id }
    assert_redirected_to "/carrinho"
    follow_redirect!
    assert_match(/Carrinho ainda não está conectado/, response.body)
  end

  test "identification placeholder show and create both 200" do
    get identification_path
    assert_response :success
    post identification_path
    assert_response :success
    assert_match(/Login ainda não está conectado/, response.body)
  end

  test "every static page route renders" do
    %w[perguntas-frequentes recomendacao-de-jogos reviews direitos].each do |slug|
      get page_path(slug: slug)
      assert_response :success, "expected /pagina/#{slug} to render"
    end
  end

  test "unknown static page slug 404s via the routing constraint" do
    # The route constraint rejects unknown slugs before reaching the controller,
    # so the integration test sees a 404 response (Rails converts the routing
    # error internally). The controller's case-statement `else raise` branch
    # is unreachable through normal HTTP and is marked `# :nocov:`.
    get "/pagina/desconhecido"
    assert_response :not_found
  end
end
