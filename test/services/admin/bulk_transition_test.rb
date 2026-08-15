require "test_helper"

module Admin
  class BulkTransitionTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    def row_for(result, order)
      result["results"].find { |entry| entry["number"] == order.number }
    end

    def merged_order
      order = Order.create!(user: users(:confirmed), subtotal_cents: 1_000, total_cents: 1_000, payment_method: "pix")
      order.confirm_payment!(automatic: true)
      order.update!(merged_into: orders(:confirmed_paid))
      order.transition_to!("merged", automatic: true)
      order
    end

    test "never operates on a merged order: transitions and issue_label both skip it" do
      merged = merged_order

      %w[to_components issue_label].each do |event|
        result = BulkTransition.call(order_numbers: [ merged.number ], event: event, actor: users(:admin))
        row = row_for(result, merged)
        assert_equal "skipped", row["outcome"], event
        assert_equal "not_available", row["reason"], event
      end

      assert merged.reload.merged?
    end

    test "applies a plain transition to eligible orders and skips the rest" do
      paid = orders(:confirmed_paid)
      producing = orders(:producing)

      result = BulkTransition.call(order_numbers: [ paid.number, producing.number ],
                                   event: "to_components", actor: users(:admin))

      assert_equal 1, result["done"]
      assert_equal 1, result["skipped"]
      assert_equal "done", row_for(result, paid)["outcome"]
      assert_equal "awaiting_components", row_for(result, paid)["status"]
      assert_equal "not_available", row_for(result, producing)["reason"]
      assert paid.reload.awaiting_components?
      assert_equal users(:admin), paid.status_changes.chronological.last.actor
      assert producing.reload.in_production?
    end

    test "flags a producing order with a production issue" do
      producing = orders(:producing)
      result = BulkTransition.call(order_numbers: [ producing.number ], event: "flag_issue", actor: users(:admin))

      assert_equal "done", row_for(result, producing)["outcome"]
      assert producing.reload.production_issue?
    end

    test "issue_label queues the label job for in-production orders and skips the rest" do
      producing = orders(:producing)
      paid = orders(:confirmed_paid)

      result = nil
      assert_enqueued_with(job: Shipping::EmitLabelsJob, args: [ [ producing.id ] ]) do
        result = BulkTransition.call(order_numbers: [ producing.number, paid.number ],
                                     event: "issue_label", actor: users(:admin))
      end

      assert_equal 1, result["queued"]
      assert_equal 1, result["skipped"]
      assert_equal "queued", row_for(result, producing)["outcome"]
      assert_equal "not_available", row_for(result, paid)["reason"]
      assert producing.reload.in_production?
    end

    test "issue_label enqueues nothing when no order is in production" do
      paid = orders(:confirmed_paid)

      assert_no_enqueued_jobs do
        result = BulkTransition.call(order_numbers: [ paid.number ], event: "issue_label", actor: users(:admin))
        assert_equal "skipped", row_for(result, paid)["outcome"]
      end
    end

    test "an unknown event skips every order" do
      paid = orders(:confirmed_paid)
      result = BulkTransition.call(order_numbers: [ paid.number ], event: "nope", actor: users(:admin))

      assert_equal "unknown_event", row_for(result, paid)["reason"]
      assert paid.reload.payment_confirmed?
    end

    test "an empty selection yields no results" do
      result = BulkTransition.call(order_numbers: [], event: "to_components", actor: users(:admin))

      assert_empty result["results"]
      assert_equal 0, result["done"]
    end
    test "start_return opens the inbound leg and queues each label" do
      order = orders(:delivered)

      result = Admin::BulkTransition.call(order_numbers: [ order.number ], event: "start_return", actor: users(:admin))

      assert_equal 1, result["queued"]
      assert_equal "awaiting_return", result["results"].sole["status"]
      assert order.reload.awaiting_return?
      assert order.return_shipment.inbound?
    end

    test "start_return skips an order that cannot be returned, naming the reason" do
      result = Admin::BulkTransition.call(order_numbers: [ orders(:producing).number ], event: "start_return", actor: users(:admin))

      assert_equal 1, result["skipped"]
      assert_equal "not_returnable", result["results"].sole["reason"]
      assert orders(:producing).reload.in_production?
    end

    test "start_return is a no-op the second time, because the order left the eligible statuses" do
      order = orders(:delivered)
      Shipping::StartReturn.call(order: order)
      shipment_id = order.reload.return_shipment.id

      result = Admin::BulkTransition.call(order_numbers: [ order.number ], event: "start_return", actor: users(:admin))

      assert_equal "not_returnable", result["results"].sole["reason"]
      assert_equal shipment_id, order.reload.return_shipment.id
    end
  end
end
