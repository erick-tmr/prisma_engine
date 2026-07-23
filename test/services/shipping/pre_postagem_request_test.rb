require "test_helper"

module Shipping
  class PrePostagemRequestTest < ActiveSupport::TestCase
    test "builds the request from the shipment snapshot, user contact and line items" do
      request = Shipping::PrePostagemRequest.from_shipment(shipments(:awaiting))

      assert_equal :pac, request.service
      assert_equal "PG-202606140001", request.observacao

      recipient = request.recipient
      assert_equal "Cliente Confirmado", recipient[:nome]
      assert_equal "11", recipient[:dddCelular]
      assert_equal "999998888", recipient[:celular]
      assert_equal "confirmed@example.com", recipient[:email]
      assert_equal "52998224725", recipient[:cpfCnpj]
      assert_equal "01310100", recipient.dig(:endereco, :cep)
      assert_equal "Apto 12", recipient.dig(:endereco, :complemento)

      item = request.items.sole
      assert_equal "Cartucho Game Boy - The Legend of Zelda: Link's Awakening DX", item[:conteudo]
      assert_equal "1", item[:quantidade]
      assert_equal "320.00", item[:valor]

      dimensions = request.dimensions
      assert_equal "120", dimensions[:pesoInformado]
      assert_equal "4", dimensions[:alturaInformada]
      assert_equal "16", dimensions[:larguraInformada]
      assert_equal "24", dimensions[:comprimentoInformado]
    end

    test "omits a blank complemento from the recipient address" do
      request = Shipping::PrePostagemRequest.from_shipment(shipments(:confirmed_paid))

      assert_not request.recipient[:endereco].key?(:complemento)
    end

    test "omits obs when the shipment has no receiver note" do
      request = Shipping::PrePostagemRequest.from_shipment(shipments(:awaiting))

      assert_not request.recipient.key?(:obs)
    end

    test "maps the shipment receiver_obs to the recipient obs" do
      shipment = shipments(:awaiting)
      shipment.update!(receiver_obs: "Entregar na portaria")

      request = Shipping::PrePostagemRequest.from_shipment(shipment)

      assert_equal "Entregar na portaria", request.recipient[:obs]
    end

    test "strips emoji and non-Latin-1 characters from the content declaration" do
      order = Order.create!(user: users(:confirmed), subtotal_cents: 50, total_cents: 50)
      order.order_items.create!(
        name: "Pokemon - Yellow Version Inglês 🇺🇸 - Sem Caixa 🔴", unit_price_cents: 50, quantity: 1
      )
      order.create_shipment!(
        service: "pac", shipping_cents: 0, weight_grams: 100, height_cm: 4, width_cm: 16, length_cm: 24,
        receiver_name: "Cliente", receiver_cpf: "52998224725", zip: "01310100",
        street: "Av. Paulista", number: "1", neighborhood: "Centro", city: "São Paulo", state: "SP"
      )

      request = Shipping::PrePostagemRequest.from_shipment(order.shipment)

      assert_equal "Pokemon - Yellow Version Inglês - Sem Caixa", request.items.sole[:conteudo]
    end
  end
end
