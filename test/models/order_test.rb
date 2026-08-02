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

  def order_in_delivery_issue
    order = build_order
    order.save!
    %w[payment_confirmed in_production label_issued shipped delivery_issue].each do |step|
      order.transition_to!(step)
    end
    order
  end

  test "a fully-populated record is valid and starts awaiting payment" do
    order = build_order
    assert order.valid?, order.errors.full_messages.to_sentence
    assert order.awaiting_payment?
  end

  test "an observation over the checkout limit is rejected on create" do
    order = build_order(observation: "a" * (Order::OBSERVATION_LIMIT + 1))
    assert_not order.valid?
    assert_includes order.errors.attribute_names, :observation
  end

  test "an observation at the checkout limit is accepted" do
    order = build_order(observation: "a" * Order::OBSERVATION_LIMIT)
    assert order.valid?, order.errors.full_messages.to_sentence
  end

  test "create generates a PG-##### number with five random digits" do
    order = build_order
    order.save!
    assert_match(/\APG-\d{5}\z/, order.number)
  end

  test "a colliding draw is retried until a free number is found" do
    srand(1)
    taken = build_order
    taken.save!
    srand(1)
    order = build_order
    order.save!
    assert_not_equal taken.number, order.number
  end

  test "exhausting every draw raises rather than saving a duplicate" do
    srand(2)
    Array.new(Order::NUMBER_ATTEMPTS) { "PG-#{format('%05d', rand(100_000))}" }
      .uniq.each { |n| build_order(number: n).save! }
    srand(2)
    assert_raises(Order::UnallocatableNumber) { build_order.save! }
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

  test "advance_to_label_issued! moves an in-production order to label_issued" do
    order = orders(:producing)

    order.advance_to_label_issued!(automatic: true)
    assert order.reload.label_issued?
  end

  test "advance_to_label_issued! is idempotent once already label_issued" do
    order = orders(:producing)
    order.advance_to_label_issued!(automatic: true)

    assert_nothing_raised { order.advance_to_label_issued!(automatic: true) }
    assert order.reload.label_issued?
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

  test "cancel_by_customer! parks an awaiting_components order in awaiting_refund" do
    order = build_order
    order.save!
    order.confirm_payment!
    order.transition_to!("awaiting_components")
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

  test "cancellable? while awaiting, confirmed or awaiting components, not once in production" do
    order = build_order
    order.save!
    assert order.cancellable?
    order.confirm_payment!
    assert order.cancellable?
    order.transition_to!("awaiting_components")
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

  test "a shipped order can branch to delivery_issue" do
    order = order_in_delivery_issue
    assert order.delivery_issue?
  end

  test "delivery_issue resolves to refund, reship or cancel" do
    %w[awaiting_refund shipped cancelled].each do |target|
      order = order_in_delivery_issue
      order.transition_to!(target)
      assert_equal target, order.status
    end
  end

  test "delivery_issue refuses a non-resolution edge" do
    order = order_in_delivery_issue
    assert_raises(Order::InvalidTransition) { order.transition_to!("delivered") }
  end

  test "creating an order records an initial automatic status change" do
    order = build_order
    order.save!
    change = order.status_changes.sole
    assert_nil change.from_status
    assert_equal "awaiting_payment", change.to_status
    assert change.automatic
    assert_nil change.actor
  end

  test "transition_to! records the move with the acting operator" do
    order = build_order
    order.save!
    order.confirm_payment!
    order.transition_to!("in_production", actor: users(:admin))
    change = order.status_changes.chronological.last
    assert_equal "payment_confirmed", change.from_status
    assert_equal "in_production", change.to_status
    assert_equal users(:admin), change.actor
    assert_not change.automatic
  end

  test "transition_to! lets only one of two concurrent callers through" do
    order = build_order
    order.save!
    order.confirm_payment!
    rival = Order.find(order.id)

    assert rival.transition_to!("in_production", actor: users(:admin))

    assert_no_difference -> { order.status_changes.count } do
      assert_not order.transition_to!("in_production", actor: users(:admin))
    end
    assert_equal 1, order.status_changes.where(to_status: "in_production").count
  end

  test "a lost transition still refreshes the caller's status so callers do not loop" do
    order = build_order
    order.save!
    order.confirm_payment!
    Order.find(order.id).transition_to!("in_production", automatic: true)

    order.transition_to!("in_production", automatic: true)

    assert_equal "in_production", order.status
  end

  test "transition_to! can flag an automatic move with no actor" do
    order = build_order
    order.save!
    order.confirm_payment!(automatic: true)
    change = order.status_changes.chronological.last
    assert_equal "payment_confirmed", change.to_status
    assert change.automatic
    assert_nil change.actor
  end

  test "a refused transition records no status change" do
    order = build_order
    order.save!
    assert_no_difference -> { order.status_changes.count } do
      assert_raises(Order::InvalidTransition) { order.transition_to!("delivered") }
    end
  end

  test "an order cannot be destroyed: it is kept for history" do
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

  test "each mergeable state can transition to merged" do
    %w[payment_confirmed awaiting_components production_issue].each do |state|
      order = build_order
      order.save!
      order.update_column(:status, state)
      order.transition_to!("merged")
      assert order.reload.merged?
    end
  end

  test "merged is terminal" do
    order = build_order
    order.save!
    order.update_column(:status, "payment_confirmed")
    order.transition_to!("merged")
    assert_raises(Order::InvalidTransition) { order.transition_to!("in_production") }
  end

  test "a merged order counts as paid" do
    order = build_order
    order.save!
    order.update_column(:status, "merged")
    assert_equal :paid, order.payment_status
    assert_not order.cancellable?
  end

  test "paid scopes to every state the money has cleared" do
    assert_equal Order::STATUSES - %w[awaiting_payment cancelled merged], Order::PAID_STATUSES

    paid = build_order
    paid.save!
    paid.update_column(:status, "payment_confirmed")
    assert_includes Order.paid, paid
  end

  test "paid excludes unpaid and cancelled orders" do
    %w[awaiting_payment cancelled].each do |status|
      order = build_order
      order.save!
      order.update_column(:status, status)
      assert_not_includes Order.paid, order, "#{status} should not count as paid"
    end
  end

  test "paid excludes merged orders, whose value already sits in their master" do
    order = build_order
    order.save!
    order.update_column(:status, "merged")

    assert_not_includes Order.paid, order
    assert_equal :paid, order.payment_status,
                 "the customer did pay; only the revenue sum skips it, to avoid double counting"
  end

  test "mergeable scopes to the three eligible states, oldest first" do
    user = User.create!(
      email: "merge-scope@example.com", password: "password123",
      full_name: "Merge Scope", cpf: "39053344705", phone: "11900000000", confirmed_at: 1.day.ago
    )
    older = user.orders.create!(base_attrs)
    older.update_columns(status: "production_issue", created_at: 3.days.ago)
    newer = user.orders.create!(base_attrs)
    newer.update_columns(status: "payment_confirmed", created_at: 1.day.ago)
    user.orders.create!(base_attrs)

    assert_equal [ older.id, newer.id ], user.orders.mergeable.pluck(:id)
  end

  test "merged_into links an absorbed order back to its master" do
    master = build_order
    master.save!
    absorbed = build_order
    absorbed.save!
    absorbed.update!(merged_into: master)
    assert_equal master, absorbed.reload.merged_into
    assert_includes master.merged_orders, absorbed
  end
end
