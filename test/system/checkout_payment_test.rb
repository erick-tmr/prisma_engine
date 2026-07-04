require "application_system_test_case"

class CheckoutPaymentTest < ApplicationSystemTestCase
  setup do
    Rails.cache.clear
    stub_cep
    stub_preco_prazo
    stub_infinitepay_links
    @user = users(:confirmed)
    @user.addresses.create!(
      receiver_name: "Cliente Confirmado", receiver_cpf: "52998224725",
      zip: "01310100", street: "Av. Paulista", number: "1578",
      neighborhood: "Bela Vista", city: "São Paulo", state: "SP"
    )
    login_as_user(@user)
  end

  test "confirming payment creates the order and lands on the local return page" do
    visit product_path(slug: products(:yellow).slug)
    click_button "Adicionar ao carrinho"

    visit checkout_path
    assert_selector "[data-ship-opts] [data-ship-opt]", minimum: 1

    orders_before = @user.orders.count
    find("[data-obs-none]").click
    find("[data-pay-btn]").click

    assert_current_path(%r{/checkout/retorno}, wait: 10)
    assert_equal orders_before + 1, @user.orders.count
  end
end
