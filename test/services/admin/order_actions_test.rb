require "test_helper"

module Admin
  class OrderActionsTest < ActiveSupport::TestCase
    test "delivery_issue offers nothing: the object is with Correios, not with us" do
      assert_empty OrderActions.available_for("delivery_issue")
    end

    test "a returned order can only be cancelled" do
      actions = OrderActions.available_for("returned")

      assert_equal %w[cancel], actions.map(&:id)
      assert_equal [ true ], actions.map(&:danger)
    end

    test "lookup finds an action by id and returns nil for an unknown one" do
      assert_equal "cancelled", OrderActions.lookup("cancel").to
      assert_nil OrderActions.lookup("nope")
    end

    test "reship is withheld until a second outbound shipment can be minted" do
      assert_nil OrderActions.lookup("reship")

      %w[delivery_issue returned].each do |status|
        assert_empty OrderActions.available_for(status).select { |action| action.to == "shipped" },
                     "expected #{status} to offer no route back to shipped"
      end
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
      end
    end

    test "the package coming back is a Correios event, never an operator button" do
      assert_nil OrderActions.lookup("mark_returned")

      %w[shipped delivered delivery_issue awaiting_return returning].each do |status|
        assert_empty OrderActions.available_for(status).select { |action| action.to == "returned" },
                     "expected #{status} to offer no manual route to returned"
      end
    end

    test "available_for is empty for a merged order" do
      assert_empty OrderActions.available_for("merged")
    end
  end
end
