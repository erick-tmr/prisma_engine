require "test_helper"

module Shipping
  class CancelReturnTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @order = orders(:delivered)
      Shipping::StartReturn.call(order: @order)
      @order.reload
    end

    test "drops the inbound leg and puts the order back with the customer" do
      shipment_id = @order.return_shipment.id

      assert Shipping::CancelReturn.call(order: @order, actor: users(:admin)).success?
      assert @order.reload.delivered?
      assert_nil Shipment.find_by(id: shipment_id)
      assert_nil @order.return_shipment
    end

    test "takes the return label with it" do
      label = @order.return_shipment.shipping_label
      label.mark_ready!(filename: "devolucao.pdf", pdf: "x")

      Shipping::CancelReturn.call(order: @order)

      assert_nil ShippingLabel.find_by(id: label.id)
    end

    test "frees the unique index so a fresh return can be authorized" do
      Shipping::CancelReturn.call(order: @order)

      assert Shipping::StartReturn.call(order: @order.reload).success?
    end

    test "refuses once the customer has posted the package" do
      @order.return_shipment.update!(posted_at: Time.current)

      result = Shipping::CancelReturn.call(order: @order)

      assert_equal :already_posted, result.error
      assert @order.reload.awaiting_return?
    end

    test "can still be cancelled while the return is in transit" do
      @order.transition_to!("returning", automatic: true)

      assert Shipping::CancelReturn.call(order: @order.reload).success?
      assert @order.reload.delivered?
    end

    test "refuses an order with no return in progress" do
      result = Shipping::CancelReturn.call(order: orders(:producing))

      assert_equal :not_cancellable, result.error
    end

    test "refuses when the status fits but the inbound shipment is gone" do
      @order.return_shipment.destroy!

      result = Shipping::CancelReturn.call(order: @order.reload)

      assert_equal :no_return, result.error
    end
  end
end
