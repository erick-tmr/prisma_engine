require "application_system_test_case"

class AdminOrderMergeTest < ApplicationSystemTestCase
  include SystemStubs

  setup do
    @client = User.create!(
      email: "merge-e2e@example.com", password: "password123",
      full_name: "Cliente Mescla", cpf: "39053344705", phone: "11900000000", confirmed_at: 1.day.ago
    )
    @master   = paid_order(status: "in_production", created: 3.days.ago)
    @absorbed = paid_order(status: "payment_confirmed", created: 1.day.ago)
    stub_preco_prazo
  end

  def paid_order(status:, created:)
    order = @client.orders.create!(subtotal_cents: 5_000, total_cents: 6_500)
    order.update_columns(status: status, created_at: created)
    order.order_items.create!(name: "Cartucho #{status}", unit_price_cents: 5_000, quantity: 1)
    order.create_shipment!(
      service: "pac", shipping_cents: 1_500, weight_grams: 250,
      receiver_name: "Cliente", receiver_cpf: "39053344705", zip: "01310100",
      street: "Av. Paulista", number: "1000", neighborhood: "Bela Vista", city: "São Paulo", state: "SP"
    )
    order
  end

  test "an operator folds another order into the one on the bench" do
    login_as_user(users(:admin))
    visit admin_order_path(@master)

    within "[data-merge-panel]" do
      assert_selector "[data-merge-open][disabled]"
      find("[data-merge-row]", text: @absorbed.number).click
      assert_selector "[data-merge-title]", text: "1 pedido selecionado"
      find("[data-merge-open]").click
    end

    within "[data-merge-overlay]" do
      assert_selector "h3", text: "Mesclar 1 pedido em #{@master.number}?"
      find("[data-merge-confirm]").click
    end

    assert_selector ".od-flash--ok", text: "1 pedido mesclado em #{@master.number}"
    assert_selector ".pill.pill-lg", text: I18n.t("account.orders.states.payment_confirmed.label")
    assert_selector ".hist-body .note", text: "Mesclou #{@absorbed.number}"
    assert @absorbed.reload.merged?
    assert_equal 2, @master.reload.order_items.count
  end

  test "Cancelar closes the confirm modal without merging" do
    login_as_user(users(:admin))
    visit admin_order_path(@master)

    find("[data-merge-row]", text: @absorbed.number).click
    find("[data-merge-open]").click
    within("[data-merge-overlay]") { find("[data-merge-close]").click }

    assert_no_selector "[data-merge-overlay]"
    assert_not @absorbed.reload.merged?
  end
end
