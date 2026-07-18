require "test_helper"

module Shipping
  class CombinedWeightTest < ActiveSupport::TestCase
    OVERHEAD = Shipping::PACKAGE_OVERHEAD_GRAMS

    def cart
      Cart::Bag.new.add(product: products(:yellow), quantity: 1)
    end

    test "strips each existing box overhead and adds exactly one back via the cart" do
      orders = [ orders(:confirmed_paid), orders(:producing) ]
      expected = (250 - OVERHEAD) + (250 - OVERHEAD) + Shipping::PackageWeight.call(cart)
      assert_equal expected, Shipping::CombinedWeight.call(orders: orders, cart: cart)
    end

    test "uses the persisted shipment weight, so custom-order items with no product weight still fold in" do
      user = User.create!(
        email: "cw@example.com", password: "password123",
        full_name: "CW", cpf: "39053344705", phone: "11900000000", confirmed_at: 1.day.ago
      )
      order = user.orders.create!(subtotal_cents: 19_000, total_cents: 21_990, status: "payment_confirmed")
      order.create_shipment!(
        service: "pac", shipping_cents: 2990, weight_grams: 300,
        height_cm: 4, width_cm: 16, length_cm: 24,
        receiver_name: "CW", receiver_cpf: "39053344705", zip: "01310100",
        street: "Rua", number: "1", neighborhood: "Centro", city: "São Paulo", state: "SP"
      )
      order.order_items.create!(name: "Pedido custom", unit_price_cents: 19_000, quantity: 1, requested_game: "Zelda")

      assert_equal 300, Shipping::CombinedWeight.call(orders: [ order ], cart: Cart::Bag.new)
    end
  end
end
