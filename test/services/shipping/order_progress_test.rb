require "test_helper"

module Shipping
  class OrderProgressTest < ActiveSupport::TestCase
    include ActionMailer::TestHelper

    # Order statuses reached by walking the real transition graph.
    PATHS = {
      "label_issued"     => %w[payment_confirmed in_production label_issued],
      "shipped"          => %w[payment_confirmed in_production label_issued shipped],
      "delivered"        => %w[payment_confirmed in_production label_issued shipped delivered],
      "production_issue" => %w[payment_confirmed in_production production_issue],
      "delivery_issue"   => %w[payment_confirmed in_production label_issued shipped delivery_issue],
      "returned"         => %w[payment_confirmed in_production label_issued shipped returned],
      "awaiting_refund"  => %w[payment_confirmed awaiting_refund],
      "cancelled"        => %w[cancelled]
    }.freeze

    test "in_transit advances a label_issued order to shipped" do
      order, shipment = order_with_shipment("label_issued", :in_transit)

      assert_difference -> { order.status_changes.count }, 1 do
        Shipping::OrderProgress.apply(shipment)
      end

      assert order.reload.shipped?
      change = order.status_changes.chronological.last
      assert_equal "shipped", change.to_status
      assert change.automatic
      assert_nil change.actor
    end

    test "delivered walks label_issued through shipped to delivered, recording both" do
      order, shipment = order_with_shipment("label_issued", :delivered)

      assert_difference -> { order.status_changes.count }, 2 do
        Shipping::OrderProgress.apply(shipment)
      end

      assert order.reload.delivered?
      last_two = order.status_changes.chronological.last(2)
      assert_equal %w[shipped delivered], last_two.map(&:to_status)
      assert last_two.all?(&:automatic)
      assert(last_two.all? { |change| change.actor.nil? })
    end

    test "delivered advances a shipped order one step and emails the customer" do
      order, shipment = order_with_shipment("shipped", :delivered)

      assert_enqueued_email_with OrderMailer, :delivered, args: [ order ] do
        assert_difference -> { order.status_changes.count }, 1 do
          Shipping::OrderProgress.apply(shipment)
        end
      end

      assert order.reload.delivered?
    end

    test "returned walks to shipped then marks the order returned" do
      order, shipment = order_with_shipment("label_issued", :returned)

      Shipping::OrderProgress.apply(shipment)

      assert order.reload.returned?
      assert_equal %w[shipped returned],
                   order.status_changes.chronological.last(2).map(&:to_status)
    end

    test "returned marks the order returned straight from shipped and emails the customer" do
      order, shipment = order_with_shipment("shipped", :returned)

      assert_enqueued_email_with OrderMailer, :returned, args: [ order ] do
        Shipping::OrderProgress.apply(shipment)
      end

      assert order.reload.returned?
    end

    test "a flagged order becomes returned once the package comes back to us" do
      order, shipment = order_with_shipment("delivery_issue", :returned)

      assert_enqueued_email_with OrderMailer, :returned, args: [ order ] do
        assert_difference -> { order.status_changes.count }, 1 do
          Shipping::OrderProgress.apply(shipment)
        end
      end

      assert order.reload.returned?
    end

    test "a returned order is not dragged back onto the shipping leg" do
      order, shipment = order_with_shipment("returned", :returned)

      assert_no_difference -> { order.status_changes.count } do
        2.times { Shipping::OrderProgress.apply(shipment) }
      end
      assert order.reload.returned?
    end

    test "delivery_issue tracking flags the order and emails the customer" do
      order, shipment = order_with_shipment("shipped", :delivery_issue)

      assert_enqueued_email_with OrderMailer, :delivery_issue, args: [ order ] do
        Shipping::OrderProgress.apply(shipment)
      end

      assert order.reload.delivery_issue?
    end

    test "delivery_issue tracking walks a label_issued order through shipped first" do
      order, shipment = order_with_shipment("label_issued", :delivery_issue)

      Shipping::OrderProgress.apply(shipment)

      assert order.reload.delivery_issue?
      assert_equal %w[shipped delivery_issue],
                   order.status_changes.chronological.last(2).map(&:to_status)
    end

    test "a flagged order stays put while tracking keeps reporting the issue" do
      order, shipment = order_with_shipment("delivery_issue", :delivery_issue)

      assert_no_difference -> { order.status_changes.count } do
        2.times { Shipping::OrderProgress.apply(shipment) }
      end
      assert order.reload.delivery_issue?
    end

    test "a flagged order resumes to delivered once the customer collects it" do
      order, shipment = order_with_shipment("delivery_issue", :delivered)

      assert_enqueued_email_with OrderMailer, :delivered, args: [ order ] do
        assert_difference -> { order.status_changes.count }, 1 do
          Shipping::OrderProgress.apply(shipment)
        end
      end

      assert order.reload.delivered?
    end

    test "a flagged order is not dragged back to shipped by stale movement" do
      order, shipment = order_with_shipment("delivery_issue", :in_transit)

      assert_no_difference -> { order.status_changes.count } do
        Shipping::OrderProgress.apply(shipment)
      end
      assert order.reload.delivery_issue?
    end

    test "is idempotent: a re-run makes no further change" do
      order, shipment = order_with_shipment("label_issued", :delivered)
      Shipping::OrderProgress.apply(shipment)

      assert_no_difference -> { order.status_changes.count } do
        Shipping::OrderProgress.apply(shipment)
      end
      assert order.reload.delivered?
    end

    test "never drags an off-leg order onto the shipping leg" do
      %w[cancelled awaiting_refund production_issue].each do |status|
        order, shipment = order_with_shipment(status, :delivered)

        assert_no_difference -> { order.status_changes.count }, status do
          Shipping::OrderProgress.apply(shipment)
        end
        assert_equal status, order.reload.status
      end
    end

    test "does not move an order already past the tracking state" do
      order, shipment = order_with_shipment("delivered", :in_transit)

      assert_no_difference -> { order.status_changes.count } do
        Shipping::OrderProgress.apply(shipment)
      end
      assert order.reload.delivered?
    end

    test "does not flag delivery_issue on an already-delivered order" do
      order, shipment = order_with_shipment("delivered", :returned)

      assert_no_difference -> { order.status_changes.count } do
        Shipping::OrderProgress.apply(shipment)
      end
      assert order.reload.delivered?
    end

    test "ignores tracking states that carry no order signal" do
      %i[pending unavailable].each do |state|
        order, shipment = order_with_shipment("label_issued", state)

        assert_no_difference -> { order.status_changes.count }, state.to_s do
          Shipping::OrderProgress.apply(shipment)
        end
        assert order.reload.label_issued?
      end
    end

    private

    def order_with_shipment(order_status, tracking_state)
      order = Order.create!(user: users(:confirmed), subtotal_cents: 32_000, total_cents: 34_990)
      shipment = Shipment.create!(order: order, service: "pac", shipping_cents: 2_990)
      PATHS.fetch(order_status).each { |step| order.transition_to!(step) }
      shipment.update!(tracking_state: tracking_state)
      [ order.reload, shipment ]
    end
  end
end
