require "test_helper"

module Admin
  class OrderActionsTest < ActiveSupport::TestCase
    test "delivery_issue offers returned and reship, but no cancel while Correios holds the object" do
      actions = OrderActions.available_for("delivery_issue")

      assert_equal %w[mark_returned reship], actions.map(&:id)
      assert_equal %w[returned shipped], actions.map(&:to)
      assert_equal [ false, false ], actions.map(&:danger)
    end

    test "a returned order can be reshipped or cancelled, but not returned again" do
      actions = OrderActions.available_for("returned")

      assert_equal %w[reship cancel], actions.map(&:id)
      assert_equal [ false, true ], actions.map(&:danger)
    end

    test "lookup finds an action by id and returns nil for an unknown one" do
      assert_equal "shipped", OrderActions.lookup("reship").to
      assert_nil OrderActions.lookup("nope")
    end

    test "issue_label is not an operator action; labels are issued in batch" do
      assert_nil OrderActions.lookup("issue_label")
      assert_equal %w[flag_issue cancel], OrderActions.available_for("in_production").map(&:id)
    end

    test "cancel is offered from every status where we still hold the item" do
      Order::CANCELLABLE_STATUSES.each do |status|
        assert_includes OrderActions.available_for(status).map(&:id), "cancel",
                        "expected #{status} to offer cancel"
      end
    end

    test "cancel is withheld once the package is out until it comes back to us" do
      %w[shipped delivered delivery_issue].each do |status|
        assert_not_includes OrderActions.available_for(status).map(&:id), "cancel",
                            "expected #{status} not to offer cancel"
        assert_includes OrderActions.available_for(status).map(&:id), "mark_returned"
      end
    end

    test "available_for is empty for a merged order" do
      assert_empty OrderActions.available_for("merged")
    end
  end
end
