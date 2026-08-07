require "test_helper"

module Admin
  class LabelFeedbackTest < ActiveSupport::TestCase
    setup { @order = orders(:producing) }

    def feedback_for(order)
      Admin::LabelFeedback.new(order.reload)
    end

    test "an order without a label yet is idle and shows no code" do
      assert_equal "idle", feedback_for(@order).state
      assert_nil feedback_for(@order).code
      assert_not feedback_for(@order).in_flight?
    end

    test "an order without a shipment is idle" do
      order = orders(:awaiting)
      order.shipment.destroy!

      assert_equal "idle", feedback_for(order).state
    end

    test "a pending label is queued and counts as in flight" do
      @order.shipment.create_shipping_label!(state: :pending)

      feedback = feedback_for(@order)
      assert_equal "queued", feedback.state
      assert feedback.in_flight?
      assert_not feedback.settled?
    end

    test "every mid-saga state reads as running and names its step" do
      label = @order.shipment.create_shipping_label!(state: :prepost_created)

      Admin::LabelFeedback::RUNNING_STATES.each do |state|
        label.update!(state: state)

        feedback = feedback_for(@order)
        assert_equal "running", feedback.state, "expected #{state} to read as running"
        assert_equal state, feedback.step
        assert feedback.in_flight?
      end
    end

    test "a recorded error wins over the persisted state" do
      label = @order.shipment.create_shipping_label!(state: :prepost_confirmed)
      label.record_error!("PPN-320 destinatário inválido")

      feedback = feedback_for(@order)
      assert_equal "failed", feedback.state
      assert_equal "PPN-320 destinatário inválido", feedback.error_message
      assert feedback.settled?
      assert_not feedback.in_flight?
    end

    test "a long Correios message is truncated but keeps its code" do
      label = @order.shipment.create_shipping_label!(state: :prepost_confirmed)
      label.record_error!("PPN-320 #{"x" * 200}")

      assert_equal Admin::LabelFeedback::ERROR_LIMIT, feedback_for(@order).error_message.length
      assert_match(/\APPN-320/, feedback_for(@order).error_message)
    end

    test "a ready label on a label_issued order is done and shows the tracking code" do
      order = orders(:labeled)
      order.shipment.update!(tracking_code: "PG515656027BR")

      feedback = feedback_for(order)
      assert_equal "done", feedback.state
      assert_equal "PG515656027BR", feedback.code
      assert feedback.settled?
    end

    test "a ready label on an already shipped order falls back to the plain code" do
      order = orders(:shipped_order)
      order.shipment.create_shipping_label!(state: :ready)
      order.shipment.update!(tracking_code: "PG515656028BR")

      assert_equal "idle", feedback_for(order).state
      assert_equal "PG515656028BR", feedback_for(order).code
    end

    test "since exposes when the current step was last written" do
      label = @order.shipment.create_shipping_label!(state: :prepost_created)

      assert_equal label.updated_at, feedback_for(@order).since
      assert_equal @order.number, feedback_for(@order).number
    end

    test "an order with no label has no step and no error message" do
      feedback = feedback_for(@order)

      assert_nil feedback.step
      assert_nil feedback.since
      assert_equal "", feedback.error_message
    end
  end
end
