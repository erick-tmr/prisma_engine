require "test_helper"

module Checkout
  class MergeQuoteTest < ActiveSupport::TestCase
    PRECO_URL = "#{Correios::Api::BASE_URL}/preco/v1/nacional".freeze
    PRAZO_URL = "#{Correios::Api::BASE_URL}/prazo/v1/nacional".freeze

    setup do
      Rails.cache.clear
      @user = User.create!(
        email: "mq@example.com", password: "password123",
        full_name: "MQ Cliente", cpf: "39053344705", phone: "11900000000", confirmed_at: 1.day.ago
      )
    end

    teardown { Rails.cache.clear }

    def cart
      @cart ||= Cart::Bag.new.add(product: products(:yellow), quantity: 1)
    end

    def add_order(status:, frete:, weight: 250, service: "pac", created: 1.day.ago)
      order = @user.orders.create!(subtotal_cents: 19_000, total_cents: 19_000 + frete, status: status)
      order.update_column(:created_at, created)
      order.create_shipment!(
        service: service, shipping_cents: frete, weight_grams: weight,
        height_cm: 4, width_cm: 16, length_cm: 24,
        receiver_name: "MQ", receiver_cpf: "39053344705", zip: "01310100",
        street: "Rua", number: "1", neighborhood: "Centro", city: "São Paulo", state: "SP"
      )
      order
    end

    test "returns no_mergeable when the user has no eligible orders" do
      result = MergeQuote.call(user: @user, cart: cart)
      assert_not result.eligible?
      assert_equal :no_mergeable, result.error
      assert_equal cart.subtotal_cents, result.subtotal_cents
    end

    test "charges the combined frete minus only the master's paid frete" do
      master   = add_order(status: "payment_confirmed", frete: 500, service: "pac", created: 3.days.ago)
      absorbed = add_order(status: "awaiting_components", frete: 700, service: "pac", created: 1.day.ago)
      stub_preco_prazo(all_eligible: true)

      result = MergeQuote.call(user: @user, cart: cart)

      assert result.eligible?
      assert_equal master, result.master
      assert_equal [ absorbed.id ], result.absorbed_orders.map(&:id)
      assert_equal "pac", result.service
      assert_equal 2384, result.combined_shipping_cents
      assert_equal 1200, result.paid_fretes_cents
      assert_equal 2384 - 500, result.delta_cents
      assert_equal cart.subtotal_cents, result.subtotal_cents
      assert_equal cart.subtotal_cents + (2384 - 500), result.amount_cents
      assert_equal (198 + 198) + Shipping::PackageWeight.call(cart), result.combined_weight_grams
    end

    test "never ships below a merged order's service (upgrade only)" do
      add_order(status: "payment_confirmed", frete: 500, service: "pac", created: 3.days.ago)
      add_order(status: "awaiting_components", frete: 700, service: "sedex", created: 1.day.ago)
      stub_preco_prazo(all_eligible: true)

      result = MergeQuote.call(user: @user, cart: cart)
      assert_equal "sedex", result.service
      assert_equal 2784, result.combined_shipping_cents
    end

    test "floors the delta at zero when already-paid frete covers the combined shipment" do
      add_order(status: "payment_confirmed", frete: 4000, created: 2.days.ago)
      stub_preco_prazo(all_eligible: true)

      result = MergeQuote.call(user: @user, cart: cart)
      assert_equal 0, result.delta_cents
      assert_equal cart.subtotal_cents, result.amount_cents
    end

    test "reports the savings versus shipping each order separately" do
      add_order(status: "payment_confirmed", frete: 1500, created: 3.days.ago)
      add_order(status: "awaiting_components", frete: 1500, created: 2.days.ago)
      stub_preco_prazo(all_eligible: true)

      result = MergeQuote.call(user: @user, cart: cart)
      assert_equal (3000 + 1415) - 2384, result.savings_cents
    end

    test "never reports negative savings" do
      add_order(status: "payment_confirmed", frete: 100, created: 2.days.ago)
      stub_preco_prazo(all_eligible: true)

      assert_equal 0, MergeQuote.call(user: @user, cart: cart).savings_cents
    end

    test "bases savings on paid frete alone when the cart cannot ship on its own" do
      add_order(status: "payment_confirmed", frete: 5000, created: 2.days.ago)
      stub_request(:post, PRECO_URL).to_return(
        { status: 200, body: eligible_preco.to_json, headers: json_headers },
        { status: 200, body: ineligible_preco.to_json, headers: json_headers }
      )
      stub_prazo

      result = MergeQuote.call(user: @user, cart: cart)
      assert_equal 5000 - 2384, result.savings_cents
    end

    test "upgrades when the master's service is too heavy for the combined parcel" do
      add_order(status: "payment_confirmed", frete: 500, service: "mini_envios", created: 2.days.ago)
      stub_preco_prazo(all_eligible: false)

      result = MergeQuote.call(user: @user, cart: cart)
      assert_equal "pac", result.service
      assert_equal 2384, result.combined_shipping_cents
    end

    test "returns shipping_unavailable when no service is eligible" do
      add_order(status: "payment_confirmed", frete: 500, created: 2.days.ago)
      stub_all_ineligible

      result = MergeQuote.call(user: @user, cart: cart)
      assert_not result.eligible?
      assert_equal :shipping_unavailable, result.error
    end

    test "returns shipping_error when Correios is down" do
      add_order(status: "payment_confirmed", frete: 500, created: 2.days.ago)
      stub_request(:post, PRECO_URL).to_return(status: 503, body: "down")
      stub_request(:post, PRAZO_URL).to_return(status: 200, body: "[]")

      result = MergeQuote.call(user: @user, cart: cart)
      assert_equal :shipping_error, result.error
    end

    private

    def json_headers
      { "Content-Type" => "application/json" }
    end

    def eligible_preco
      [
        { "coProduto" => "03220", "nuRequisicao" => "03220", "pcFinal" => "24,84" },
        { "coProduto" => "03298", "nuRequisicao" => "03298", "pcFinal" => "20,84" },
        { "coProduto" => "04227", "nuRequisicao" => "04227", "pcFinal" => "11,15" }
      ]
    end

    def ineligible_preco
      [
        { "coProduto" => "04960", "nuRequisicao" => "03220", "pcFinal" => "19,84" },
        { "coProduto" => "04961", "nuRequisicao" => "03298", "pcFinal" => "20,84" },
        { "coProduto" => "04962", "nuRequisicao" => "04227", "pcFinal" => "11,15" }
      ]
    end

    def stub_preco_prazo(all_eligible:)
      preco = eligible_preco.dup
      preco[2] = { "coProduto" => "04960", "nuRequisicao" => "04227", "pcFinal" => "18,08" } unless all_eligible
      stub_preco(preco)
      stub_prazo
    end

    def stub_all_ineligible
      stub_preco(ineligible_preco)
      stub_prazo
    end

    def stub_preco(body)
      stub_request(:post, PRECO_URL).to_return(status: 200, body: body.to_json, headers: json_headers)
    end

    def stub_prazo
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
