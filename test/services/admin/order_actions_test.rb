require "test_helper"

module Admin
  class OrderActionsTest < ActiveSupport::TestCase
    test "delivery_issue offers returned, refund, reship and a danger cancel" do
      actions = OrderActions.available_for("delivery_issue")

      assert_equal %w[mark_returned issue_refund reship cancel_issue], actions.map(&:id)
      assert_equal %w[returned awaiting_refund shipped cancelled], actions.map(&:to)
      assert_equal [ false, false, false, true ], actions.map(&:danger)
    end

    test "a returned order can be reshipped, refunded or cancelled, but not returned again" do
      actions = OrderActions.available_for("returned")

      assert_equal %w[issue_refund reship cancel_issue], actions.map(&:id)
      assert_not_includes actions.map(&:id), "mark_returned"
    end

    test "lookup finds an action by id and returns nil for an unknown one" do
      assert_equal "shipped", OrderActions.lookup("reship").to
      assert_nil OrderActions.lookup("nope")
    end

    test "issue_label is not an operator action; labels are issued in batch" do
      assert_nil OrderActions.lookup("issue_label")
      assert_equal %w[flag_issue], OrderActions.available_for("in_production").map(&:id)
    end

    test "available_for is empty for a terminal state" do
      assert_empty OrderActions.available_for("delivered")
    end
  end
end
