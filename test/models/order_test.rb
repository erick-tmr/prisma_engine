require "test_helper"

class OrderTest < ActiveSupport::TestCase
  def base_attrs(overrides = {})
    {
      subtotal_cents: 32_000,
      shipping_cents:  2_990,
      total_cents:    34_990,
      shipping_service: "pac",
      ship_receiver_name: "Cliente Confirmado",
      ship_receiver_cpf:  "52998224725",
      ship_zip:           "01310100",
      ship_street:        "Rua das Flores",
      ship_number:        "150",
      ship_complement:    "Apto 12",
      ship_neighborhood:  "Centro",
      ship_city:          "São Paulo",
      ship_state:         "SP"
    }.merge(overrides)
  end

  def build_order(overrides = {})
    Order.new(base_attrs(overrides).merge(user: users(:confirmed)))
  end

  test "a fully-populated record is valid and starts awaiting payment" do
    order = build_order
    assert order.valid?, order.errors.full_messages.to_sentence
    assert order.awaiting_payment?
  end

  test "create generates a PG-YYYYMMDD#### number with today's date" do
    travel_to Time.zone.local(2026, 5, 22, 10, 0, 0) do
      order = build_order
      order.save!
      assert_match(/\APG-20260522\d{4}\z/, order.number)
    end
  end

  test "a colliding draw is retried until a free number is found" do
    travel_to Time.zone.local(2026, 5, 22) do
      srand(1)
      taken = build_order
      taken.save!
      srand(1)
      order = build_order
      order.save!
      assert_not_equal taken.number, order.number
    end
  end

  test "exhausting every draw raises rather than saving a duplicate" do
    travel_to Time.zone.local(2026, 5, 22) do
      srand(2)
      Array.new(Order::NUMBER_ATTEMPTS) { "PG-20260522#{format('%04d', rand(10_000))}" }
        .uniq.each { |n| build_order(number: n).save! }
      srand(2)
      assert_raises(Order::UnallocatableNumber) { build_order.save! }
    end
  end

  test "a provided number is not overwritten" do
    order = build_order(number: "PG-202605221234")
    order.save!
    assert_equal "PG-202605221234", order.number
  end

  test "number must be unique" do
    build_order(number: "PG-202605229999").save!
    dup = build_order(number: "PG-202605229999")
    assert_not dup.valid?
    assert_includes dup.errors.attribute_names, :number
  end

  test "money totals reject negatives" do
    assert_not build_order(total_cents: -1).valid?
  end

  test "shipping_service must be one we offer" do
    assert_not build_order(shipping_service: "carrier_pigeon").valid?
    assert build_order(shipping_service: "sedex").valid?
  end

  test "placed_at mirrors created_at" do
    order = build_order
    order.save!
    assert_equal order.created_at, order.placed_at
  end

  test "shipping_address exposes the snapshot in the MockOrder hash shape" do
    order = build_order
    assert_equal(
      {
        recipient: "Cliente Confirmado", cpf: "52998224725",
        street: "Rua das Flores", number: "150", complement: "Apto 12",
        neighborhood: "Centro", city: "São Paulo", state: "SP", zip: "01310100"
      },
      order.shipping_address
    )
  end

  test "cancellable? while awaiting or confirmed, not once in production" do
    order = build_order
    order.save!
    assert order.cancellable?
    order.confirm_payment!
    assert order.cancellable?
    order.transition_to!("in_production")
    assert_not order.cancellable?
  end

  test "confirm_payment! advances to payment_confirmed" do
    order = build_order
    order.save!
    order.confirm_payment!
    assert order.payment_confirmed?
  end

  test "transition_to! follows the lifecycle graph, accepting a symbol" do
    order = build_order
    order.save!
    order.confirm_payment!
    order.transition_to!(:in_production)
    assert order.in_production?
  end

  test "transition_to! refuses an edge not in the graph" do
    order = build_order
    order.save!
    error = assert_raises(Order::InvalidTransition) { order.transition_to!("delivered") }
    assert_match "awaiting_payment → delivered", error.message
    assert order.reload.awaiting_payment?
  end

  test "destroying an order destroys its line items" do
    order = build_order
    order.save!
    order.order_items.create!(name: "Cartucho", unit_price_cents: 32_000, quantity: 1)
    assert_difference "OrderItem.count", -1 do
      order.destroy!
    end
  end

  test "cancel! moves an awaiting-payment order to cancelled" do
    order = build_order
    order.save!
    order.cancel!
    assert order.cancelled?
  end

  test "a cancelled order can be reopened straight to payment_confirmed" do
    order = build_order
    order.save!
    order.cancel!
    order.transition_to!("payment_confirmed")
    assert order.payment_confirmed?
  end

  test "payment_deadline is 24h after creation" do
    order = build_order
    order.save!
    assert_in_delta order.created_at + 24.hours, order.payment_deadline, 1.second
  end

  test "payment_expired? only once an awaiting order passes the 24h deadline" do
    order = build_order
    order.save!
    assert_not order.payment_expired?
    travel_to 25.hours.from_now do
      assert order.payment_expired?
    end
  end

  test "payment_expired? is false once the order leaves awaiting_payment" do
    order = build_order
    order.save!
    order.confirm_payment!
    travel_to 25.hours.from_now do
      assert_not order.payment_expired?
    end
  end

  test "awaiting_payment_expired scopes to stale unpaid orders only" do
    fresh = build_order
    fresh.save!
    stale = build_order
    stale.save!
    stale.update_column(:created_at, 25.hours.ago)
    paid = build_order
    paid.save!
    paid.update_column(:created_at, 25.hours.ago)
    paid.confirm_payment!

    assert_equal [ stale.id ], Order.awaiting_payment_expired.pluck(:id)
  end
end
