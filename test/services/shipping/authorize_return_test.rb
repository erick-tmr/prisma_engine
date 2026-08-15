require "test_helper"

module Shipping
  class AuthorizeReturnTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup { @order = orders(:delivered) }

    test "opens the inbound leg and starts its label" do
      result = nil

      assert_enqueued_with(job: Shipping::CreatePrePostagemJob) do
        result = Shipping::AuthorizeReturn.call(order: @order, actor: users(:admin))
      end

      assert result.success?
      assert @order.reload.awaiting_return?
      assert result.return_shipment.inbound?
      assert_equal @order.return_shipment, result.return_shipment
    end

    test "clones the box and the customer address but not the outbound lifecycle" do
      outbound = @order.shipment
      outbound.update!(tracking_code: "AA000000000BR", posted_at: Time.current, receiver_obs: "portaria")

      inbound = Shipping::AuthorizeReturn.call(order: @order).return_shipment

      assert_equal outbound.zip, inbound.zip
      assert_equal outbound.street, inbound.street
      assert_equal outbound.receiver_name, inbound.receiver_name
      assert_equal outbound.receiver_cpf, inbound.receiver_cpf
      assert_equal outbound.weight_grams, inbound.weight_grams
      assert_equal outbound.service, inbound.service
      assert_nil inbound.tracking_code
      assert_nil inbound.posted_at
      assert_nil inbound.shipping_cents
      assert_nil inbound.receiver_obs
    end

    test "a delivery_issue order can be returned too" do
      order = orders(:delivered)
      order.transition_to!("returned", automatic: true)
      order.transition_to!("shipped", automatic: true)
      order.transition_to!("delivery_issue", automatic: true)

      assert Shipping::AuthorizeReturn.call(order: order).success?
      assert order.reload.awaiting_return?
    end

    test "refuses an order that is not delivered" do
      result = Shipping::AuthorizeReturn.call(order: orders(:producing))

      assert_not result.success?
      assert_equal :not_returnable, result.error
      assert orders(:producing).reload.in_production?
    end

    test "refuses an order with no outbound shipment" do
      order = bare_order
      order.update_column(:status, "delivered")

      result = Shipping::AuthorizeReturn.call(order: order)

      assert_equal :no_shipment, result.error
    end

    test "refuses a second return while one is open" do
      Shipping::AuthorizeReturn.call(order: @order)
      @order.reload.transition_to!("delivered", automatic: true)

      result = Shipping::AuthorizeReturn.call(order: @order)

      assert_equal :already_open, result.error
    end

    test "a racing double click loses on the unique index rather than stranding a status" do
      Shipment.create!(order: @order, direction: :inbound, service: "pac")
      @order.association(:return_shipment).reset
      @order.stub(:return_shipment, nil) do
        result = Shipping::AuthorizeReturn.call(order: @order)
        assert_equal :already_open, result.error
      end

      assert @order.reload.delivered?
    end
  end
end
