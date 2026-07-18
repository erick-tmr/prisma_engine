require "application_system_test_case"

class CheckoutMergeTest < ApplicationSystemTestCase
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

  test "customer merges their open order into a new checkout" do
    visit product_path(slug: products(:yellow).slug)
    click_button "Adicionar ao carrinho"

    visit checkout_path
    assert_selector "[data-merge]"
    assert_selector ".checkout__merge-order", count: 1

    find("[data-merge-toggle]").click
    assert_selector ".checkout__merge.is-merged"
    assert_selector "#step-shipping.is-hidden", visible: :all

    find("[data-obs-none]").click

    assert_difference [ "Order.count", "OrderMerge.count" ], 1 do
      find("[data-pay-btn]").click
      assert_selector "[data-agree-modal].is-open"
      find("[data-agree-confirm]").click
      assert_current_path(%r{/checkout/retorno}, wait: 10)
    end

    carrier = Order.order(:created_at).last
    assert carrier.order_merge.present?
    assert_equal orders(:confirmed_paid), carrier.order_merge.master_order
  end
end
