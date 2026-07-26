require "test_helper"

module Checkout
  class PlaceOrderTest < ActiveSupport::TestCase
    PRECO_URL = "#{Correios::Api::BASE_URL}/preco/v1/nacional".freeze
    PRAZO_URL = "#{Correios::Api::BASE_URL}/prazo/v1/nacional".freeze

    setup do
      Rails.cache.clear
      @user = users(:confirmed)
      @address = @user.addresses.create!(
        zip: "01310100", street: "Av. Paulista", number: "1578",
        neighborhood: "Bela Vista", city: "São Paulo", state: "SP",
        receiver_name: "Cliente Confirmado", receiver_cpf: "52998224725"
      )
    end

    teardown do
      Rails.cache.clear
    end

    def populated_cart
      Cart::Bag.new.add(
        product: products(:yellow), quantity: 2,
        option_ids: [ product_options(:yellow_caixa_com).id ]
      )
    end

    def custom_order_cart
      Cart::Bag.new.add(
        product: products(:pedido_game), quantity: 1, option_ids: [],
        request: { game: "Pokemon Unbound", notes: "v2.1, carcaça roxa" }
      )
    end

    def place(overrides = {})
      PlaceOrder.call(**{
        user: @user, cart: populated_cart,
        address_id: @address.id, shipping_service: "pac"
      }.merge(overrides))
    end

    test "creates an order snapshotting totals, the chosen service price, address and items" do
      stub_preco_prazo(all_eligible: true)

      result = nil
      assert_difference [ "Order.count", "OrderItem.count" ], 1 do
        result = place
      end

      assert result.success?
      order = result.order
      assert_equal 36_000, order.subtotal_cents
      assert_equal 38_384, order.total_cents
      assert order.awaiting_payment?

      shipment = order.shipment
      assert_equal 2_384, shipment.shipping_cents
      assert_equal "pac", shipment.service
      assert_equal 7, shipment.delivery_business_days
      assert_equal Shipping::PackageWeight.call(populated_cart), shipment.weight_grams
      assert_equal "São Paulo", shipment.city
      assert_equal "01310100", shipment.zip
      assert_equal "Cliente Confirmado", shipment.receiver_name

      item = order.order_items.sole
      assert_equal products(:yellow).id, item.product_id
      assert_equal "Pokemon Yellow Version", item.name
      assert_equal 18_000, item.unit_price_cents
      assert_equal 2, item.quantity
      assert_equal [ "Caixa: Com caixa" ], item.chosen_options
      assert_nil item.requested_game
      assert_nil item.request_notes
    end

    test "snapshots the made-to-order request onto the order item" do
      stub_preco_prazo(all_eligible: true)

      item = place(cart: custom_order_cart).order.order_items.sole
      assert_equal "Pokemon Unbound", item.requested_game
      assert_equal "v2.1, carcaça roxa", item.request_notes
    end

    test "snapshots a bare option label when the option has no group" do
      products(:yellow).product_options.update_all(group_name: nil)
      stub_preco_prazo(all_eligible: true)

      item = place.order.order_items.sole
      assert_equal [ "Com caixa" ], item.chosen_options
    end

    test "stores the customer observation, trimming surrounding blanks to nil" do
      stub_preco_prazo(all_eligible: true)

      assert_equal "Entregar após as 18h", place(observation: "  Entregar após as 18h  ").order.observation
      assert_nil place(observation: "   ").order.observation
    end

    test "stores the Correios note on the shipment" do
      stub_preco_prazo(all_eligible: true)

      shipment = place(receiver_obs: "Entregar na portaria").order.shipment
      assert_equal "Entregar na portaria", shipment.receiver_obs
    end

    test "fails when the cart is empty" do
      result = PlaceOrder.call(user: @user, cart: Cart::Bag.new, address_id: @address.id, shipping_service: "pac")
      assert_not result.success?
      assert_equal :empty_cart, result.error
      assert_nil result.order
    end

    test "fails when the address is not one of the user's" do
      other = User.create!(
        email: "outro@example.com", password: "password123",
        full_name: "Outro Cliente", cpf: "39053344705", phone: "11900000000",
        confirmed_at: 1.day.ago
      )
      foreign = other.addresses.create!(
        zip: "04534003", street: "Rua X", number: "1", neighborhood: "Itaim",
        city: "São Paulo", state: "SP", receiver_name: "Outro", receiver_cpf: "39053344705"
      )
      result = place(address_id: foreign.id)
      assert_not result.success?
      assert_equal :invalid_address, result.error
    end

    test "fails when the chosen service comes back ineligible for the parcel" do
      stub_preco_prazo(all_eligible: false)
      result = place(shipping_service: "mini_envios")
      assert_not result.success?
      assert_equal :shipping_unavailable, result.error
    end

    test "fails when the service code is unknown" do
      stub_preco_prazo(all_eligible: true)
      result = place(shipping_service: "carrier_pigeon")
      assert_not result.success?
      assert_equal :shipping_unavailable, result.error
    end

    test "fails with shipping_error when Correios is unavailable" do
      stub_request(:post, PRECO_URL).to_return(status: 503, body: "down")
      stub_request(:post, PRAZO_URL).to_return(status: 200, body: "[]")
      result = place
      assert_not result.success?
      assert_equal :shipping_error, result.error
    end

    private

    def stub_preco_prazo(all_eligible:)
      preco = [
        { "coProduto" => "03220", "nuRequisicao" => "03220", "pcFinal" => "19,84" },
        { "coProduto" => "03298", "nuRequisicao" => "03298", "pcFinal" => "20,84" }
      ]
      preco << if all_eligible
        { "coProduto" => "04227", "nuRequisicao" => "04227", "pcFinal" => "11,15" }
      else
        { "coProduto" => "04960", "nuRequisicao" => "04227", "pcFinal" => "18,08" }
      end

      stub_request(:post, PRECO_URL).to_return(
        status: 200, body: preco.to_json, headers: { "Content-Type" => "application/json" }
      )
      stub_request(:post, PRAZO_URL).to_return(
        status: 200,
        body: [
          { "coProduto" => "03220", "nuRequisicao" => "03220", "prazoEntrega" => 2 },
          { "coProduto" => "03298", "nuRequisicao" => "03298", "prazoEntrega" => 7 },
          { "coProduto" => "04227", "nuRequisicao" => "04227", "prazoEntrega" => 9 }
        ].to_json,
        headers: { "Content-Type" => "application/json" }
      )
    end
  end
end
