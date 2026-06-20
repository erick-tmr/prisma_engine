require "test_helper"

class OrderTest < ActiveSupport::TestCase
  def base_attrs(overrides = {})
    {
      subtotal_cents: 32_000,
      total_cents:    34_990
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

  test "placed_at mirrors created_at" do
    order = build_order
    order.save!
    assert_equal order.created_at, order.placed_at
  end

  test "to_param is the public order number, not the id" do
    order = build_order(number: "PG-202605221234")
    order.save!
    assert_equal "PG-202605221234", order.to_param
  end

  test "recent_first orders by newest created_at" do
    old = build_order
    old.save!
    old.update_column(:created_at, 3.days.ago)
    fresh = build_order
    fresh.save!

    ids = Order.recent_first.pluck(:id)
    assert_operator ids.index(fresh.id), :<, ids.index(old.id)
  end

  test "payment_status is pending while unpaid and paid once money is in" do
    order = build_order
    order.save!
    assert_equal :pending, order.payment_status
    order.confirm_payment!
    assert_equal :paid, order.payment_status
    order.request_refund!
    assert_equal :paid, order.payment_status
    order.transition_to!("cancelled")
    assert_equal :pending, order.payment_status
  end

  test "tracking_events and shipping_visible? follow the linked shipment" do
    order = build_order
    order.save!
    assert_empty order.tracking_events
    assert_not order.shipping_visible?

    shipment = Shipment.create!(tracking_code: "PG777000111BR", order: order)
    shipment.tracking_events.create!(position: 2, event_code: "BDE", event_type: "01", occurred_at: 1.day.ago)
    shipment.tracking_events.create!(position: 1, event_code: "PO", event_type: "01", occurred_at: 3.days.ago)

    assert_equal %w[PO BDE], order.reload.tracking_events.map(&:event_code)
    assert order.shipping_visible?
  end

  test "cancel_by_customer! cancels an unpaid order outright" do
    order = build_order
    order.save!
    order.cancel_by_customer!
    assert order.cancelled?
  end

  test "cancel_by_customer! parks a paid order in awaiting_refund" do
    order = build_order
    order.save!
    order.confirm_payment!
    order.cancel_by_customer!
    assert order.awaiting_refund?
  end

  test "awaiting_refund advances to cancelled but is no longer cancellable" do
    order = build_order
    order.save!
    order.confirm_payment!
    order.request_refund!
    assert_not order.cancellable?
    order.transition_to!("cancelled")
    assert order.cancelled?
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

  test "an order cannot be destroyed — it is kept for history" do
    order = build_order
    order.save!
    assert_not order.destroy
    assert Order.exists?(order.id)
    assert_match(/cannot be deleted/i, order.errors[:base].to_sentence)
  end

  test "each order gets a unique webhook_token on create" do
    one = build_order
    one.save!
    two = build_order
    two.save!
    assert one.webhook_token.present?
    assert_not_equal one.webhook_token, two.webhook_token
  end

  test "webhook_token is stable across the cancel/reopen lifecycle" do
    order = build_order
    order.save!
    token = order.webhook_token
    order.cancel!
    order.confirm_payment!
    assert_equal token, order.reload.webhook_token
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
