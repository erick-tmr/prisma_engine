require "application_system_test_case"

class CatalogToCartTest < ApplicationSystemTestCase
  setup do
    Rails.cache.clear
    stub_external_env
    stub_cep
    stub_preco_prazo
  end

  teardown { restore_external_env }

  test "a guest adds a product, quotes shipping, and is sent to log in to finalize" do
    visit products_path
    find("a.product-card[href='#{product_path(slug: products(:yellow).slug)}']").click

    assert_selector "[data-price]"
    click_button "Adicionar ao carrinho"

    visit cart_path
    assert_selector "[data-head-count]", text: "1 item"
    within "[data-items]" do
      assert_text products(:yellow).title
    end

    find("[data-cep]").set("01310100")
    click_button "Calcular"

    assert_text "São Paulo"
    assert_selector "[data-ship-opts] [data-ship-opt]", minimum: 1
    assert_no_selector "[data-shipping].is-pending"

    within ".cart-summary__cta" do
      click_button "Finalizar compra"
    end

    assert_current_path new_user_session_path
    assert_text "Faça login ou cadastre-se"
  end
end
