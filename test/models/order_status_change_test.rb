require "test_helper"

class OrderStatusChangeTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "a notifiable status change enqueues the matching order email" do
    order = orders(:shipped_order)

    assert_enqueued_email_with OrderMailer, :delivered, args: [ order ] do
      order.transition_to!("delivered", automatic: true)
    end
  end

  test "the label_issued and shipped changes each enqueue their own email" do
    order = orders(:producing)

    assert_enqueued_email_with OrderMailer, :label_issued, args: [ order ] do
      order.transition_to!("label_issued", automatic: true)
    end

    assert_enqueued_email_with OrderMailer, :shipped, args: [ order ] do
      order.transition_to!("shipped", automatic: true)
    end
  end

  test "a status the order has already moved past sends no email" do
    order = orders(:shipped_order)
    order.update_column(:status, "delivered")

    assert_no_enqueued_emails do
      order.status_changes.create!(from_status: "label_issued", to_status: "shipped", automatic: true)
    end
  end

  test "a non-notifiable status change enqueues nothing" do
    order = orders(:confirmed_paid)

    assert_no_enqueued_emails do
      order.status_changes.create!(from_status: "payment_confirmed", to_status: "in_production", automatic: true)
    end
  end

  test "a payment_confirmed change on an order that ends up merged sends no email" do
    order = orders(:confirmed_paid)
    order.update_column(:status, "merged")

    assert_no_enqueued_emails do
      order.status_changes.create!(from_status: "awaiting_payment", to_status: "payment_confirmed", automatic: true)
    end
  end

  test "belongs to an order and the acting operator" do
    change = order_status_changes(:delivered_production)
    assert_equal orders(:delivered), change.order
    assert_equal users(:admin), change.actor
    assert_not change.automatic
  end

  test "an automatic change has no actor" do
    change = order_status_changes(:delivered_paid)
    assert change.automatic
    assert_nil change.actor
  end

  test "chronological orders by created_at then id" do
    statuses = orders(:delivered).status_changes.chronological.pluck(:to_status)
    assert_equal %w[awaiting_payment payment_confirmed in_production label_issued shipped delivered], statuses
  end
  test "the return leg notifies the customer at both steps" do
    order = orders(:delivered)

    assert_enqueued_email_with OrderMailer, :awaiting_return, args: [ order ] do
      order.transition_to!("awaiting_return")
    end

    assert_enqueued_email_with OrderMailer, :returning, args: [ order ] do
      order.transition_to!("returning")
    end
  end
end
