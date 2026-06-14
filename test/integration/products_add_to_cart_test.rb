require "test_helper"

class ProductsAddToCartTest < ActionDispatch::IntegrationTest
  test "PDP renders a pill group per ProductOption group_name with defaults selected" do
    get product_path(slug: products(:yellow).slug)
    assert_response :success

    assert_select "[data-pdp-form]" do
      assert_select ".product-detail__variants .variant-group", count: 2 # Idioma + Caixa
      assert_select "input[name='option_ids[]'][data-variant-group='Idioma']"
      assert_select "input[name='option_ids[]'][data-variant-group='Caixa']"
      # First option per group is preselected
      assert_select ".variant-group", text: /Idioma/i do
        assert_select ".variant-pill.is-selected", text: /Português BR/
      end
      assert_select ".variant-group", text: /Caixa/i do
        assert_select ".variant-pill.is-selected", text: /Com caixa/
      end
    end
  end

  test "PDP for a product with no options skips the variants block but still adds to cart" do
    get product_path(slug: products(:metroid).slug)
    assert_response :success
    assert_select ".product-detail__variants", count: 0

    post cart_items_path, params: { product_id: products(:metroid).id, quantity: 1 }
    assert_redirected_to product_path(products(:metroid))
    assert_equal "Produto adicionado ao carrinho.", flash[:cart_added]
  end

  test "the add-to-cart flash stays on the product page and links to the cart" do
    post cart_items_path, params: { product_id: products(:metroid).id, quantity: 1 }
    follow_redirect!
    assert_response :success
    assert_select ".flash--success", text: /adicionado ao carrinho/i
    assert_select ".flash a.flash__cta[href=?]", cart_path
  end

  test "POST cart_items rejects foreign option_ids that do not belong to the product" do
    foreign = product_options(:yellow_idioma_pt) # belongs to yellow, not metroid
    post cart_items_path, params: {
      product_id: products(:metroid).id, quantity: 1, option_ids: [ foreign.id ]
    }
    assert_redirected_to product_path(products(:metroid))
    # The foreign id should be filtered, so the metroid line has no options
    get cart_path
    assert_select ".cart-item", count: 1
  end
end
