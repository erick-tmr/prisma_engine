require "test_helper"

module Checkout
  class PlaceMergeOrderTest < ActiveSupport::TestCase
    PRECO_URL = "#{Correios::Api::BASE_URL}/preco/v1/nacional".freeze
    PRAZO_URL = "#{Correios::Api::BASE_URL}/prazo/v1/nacional".freeze

    setup do
      Rails.cache.clear
      @user = User.create!(
        email: "pmo@example.com", password: "password123",
        full_name: "PMO Cliente", cpf: "39053344705", phone: "11900000000", confirmed_at: 1.day.ago
      )
    end

    teardown { Rails.cache.clear }

    def cart
      @cart ||= Cart::Bag.new.add(product: products(:yellow), quantity: 1)
    end

    def add_order(status:, frete:, service: "pac", created: 1.day.ago)
      order = @user.orders.create!(subtotal_cents: 19_000, total_cents: 19_000 + frete, status: status)
      order.update_column(:created_at, created)
      order.create_shipment!(
        service: service, shipping_cents: frete, weight_grams: 250,
        height_cm: 4, width_cm: 16, length_cm: 24,
        receiver_name: "Dona Master", receiver_cpf: "39053344705", zip: "04534003",
        street: "Rua Master", number: "9", neighborhood: "Itaim", city: "São Paulo", state: "SP"
      )
      order
    end

    test "builds a carrier order + merge plan charging the cart plus the frete delta" do
      master   = add_order(status: "payment_confirmed", frete: 500, created: 3.days.ago)
      absorbed = add_order(status: "awaiting_components", frete: 700, created: 1.day.ago)
      stub_preco_prazo

      result = nil
      assert_difference [ "Order.count", "OrderMerge.count" ], 1 do
        result = PlaceMergeOrder.call(user: @user, cart: cart, observation: "Sem pressa")
      end

      assert result.success?
      carrier = result.order
      assert carrier.awaiting_payment?
      assert_equal cart.subtotal_cents, carrier.subtotal_cents
      assert_equal cart.subtotal_cents + 1884, carrier.total_cents
      assert_equal "Sem pressa", carrier.observation
      assert_equal products(:yellow).id, carrier.order_items.sole.product_id

      shipment = carrier.shipment
      assert_equal 1884, shipment.shipping_cents
      assert_equal "pac", shipment.service
      assert_equal 7, shipment.delivery_business_days
      assert_equal "04534003", shipment.zip
      assert_equal "Dona Master", shipment.receiver_name
      assert_nil shipment.receiver_obs

      plan = carrier.order_merge
      assert_equal master, plan.master_order
      assert_equal [ absorbed.id ], plan.absorbed_order_ids
      assert_equal "pac", plan.combined_service
      assert_equal 2384, plan.combined_shipping_cents
      assert_equal 1200, plan.paid_fretes_cents
      assert plan.pending?
    end

    test "carries the Correios note onto the carrier shipment" do
      add_order(status: "payment_confirmed", frete: 500, created: 3.days.ago)
      stub_preco_prazo

      result = PlaceMergeOrder.call(user: @user, cart: cart, receiver_obs: "Entregar na portaria")

      assert result.success?
      assert_equal "Entregar na portaria", result.order.shipment.receiver_obs
    end

    test "fails on an empty cart" do
      add_order(status: "payment_confirmed", frete: 500)
      result = PlaceMergeOrder.call(user: @user, cart: Cart::Bag.new)
      assert_not result.success?
      assert_equal :empty_cart, result.error
    end

    test "fails when the user has no mergeable orders" do
      stub_preco_prazo
      result = PlaceMergeOrder.call(user: @user, cart: cart)
      assert_not result.success?
      assert_equal :no_mergeable, result.error
    end

    private

    def stub_preco_prazo
      stub_request(:post, PRECO_URL).to_return(
        status: 200,
        body: [
          { "coProduto" => "03220", "nuRequisicao" => "03220", "pcFinal" => "24,84" },
          { "coProduto" => "03298", "nuRequisicao" => "03298", "pcFinal" => "20,84" },
          { "coProduto" => "04227", "nuRequisicao" => "04227", "pcFinal" => "11,15" }
        ].to_json,
        headers: { "Content-Type" => "application/json" }
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
