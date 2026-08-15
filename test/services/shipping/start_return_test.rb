require "test_helper"

module Shipping
  class StartReturnTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup { @order = orders(:delivered) }

    test "opens the inbound leg and starts its label" do
      result = nil

      assert_enqueued_with(job: Shipping::CreatePrePostagemJob) do
        result = Shipping::StartReturn.call(order: @order, actor: users(:admin))
      end

      assert result.success?
      assert @order.reload.awaiting_return?
      assert result.return_shipment.inbound?
      assert_equal @order.return_shipment, result.return_shipment
    end

    test "clones the box and the customer address but not the outbound lifecycle" do
      outbound = @order.shipment
      outbound.update!(tracking_code: "AA000000000BR", posted_at: Time.current, receiver_obs: "portaria")

      inbound = Shipping::StartReturn.call(order: @order).return_shipment

      assert_equal outbound.zip, inbound.zip
      assert_equal outbound.street, inbound.street
      assert_equal outbound.receiver_name, inbound.receiver_name
      assert_equal outbound.receiver_cpf, inbound.receiver_cpf
      assert_equal outbound.weight_grams, inbound.weight_grams
      assert_equal Shipping::DEFAULT_RETURN_SERVICE, inbound.service
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

      assert Shipping::StartReturn.call(order: order).success?
      assert order.reload.awaiting_return?
    end

    test "refuses an order that is not delivered" do
      result = Shipping::StartReturn.call(order: orders(:producing))

      assert_not result.success?
      assert_equal :not_returnable, result.error
      assert orders(:producing).reload.in_production?
    end

    test "refuses an order with no outbound shipment" do
      order = bare_order
      order.update_column(:status, "delivered")

      result = Shipping::StartReturn.call(order: order)

      assert_equal :no_shipment, result.error
    end

    test "refuses a second return while one is open" do
      Shipping::StartReturn.call(order: @order)
      @order.reload.transition_to!("delivered", automatic: true)

      result = Shipping::StartReturn.call(order: @order)

      assert_equal :already_open, result.error
    end

    test "a racing double click loses on the unique index rather than stranding a status" do
      Shipment.create!(order: @order, direction: :inbound, service: "pac")
      @order.association(:return_shipment).reset
      @order.stub(:return_shipment, nil) do
        result = Shipping::StartReturn.call(order: @order)
        assert_equal :already_open, result.error
      end

      assert @order.reload.delivered?
    end
    test "defaults to Mini Envios, whatever the parcel went out as" do
      @order.shipment.update!(service: "sedex")

      inbound = Shipping::StartReturn.call(order: @order).return_shipment

      assert_equal Shipping::DEFAULT_RETURN_SERVICE, inbound.service
      assert_equal "mini_envios", inbound.service
    end

    test "takes the service the operator picked, whatever the outbound one was" do
      @order.shipment.update!(service: "pac")

      inbound = Shipping::StartReturn.call(order: @order, service: "sedex").return_shipment

      assert_equal "sedex", inbound.service
    end

    test "a blank service falls back to the default rather than failing" do
      inbound = Shipping::StartReturn.call(order: @order, service: "").return_shipment

      assert_equal Shipping::DEFAULT_RETURN_SERVICE, inbound.service
    end

    test "refuses a service Correios does not sell us, changing nothing" do
      result = Shipping::StartReturn.call(order: @order, service: "teleport")

      assert_equal :invalid_service, result.error
      assert @order.reload.delivered?
      assert_nil @order.return_shipment
    end
    test "records the operator's reason on the order" do
      Shipping::StartReturn.call(order: @order, reason: "  Cartucho não liga  ")

      assert_equal "Cartucho não liga", @order.reload.return_reason
    end

    test "a return with no reason given leaves the column empty rather than blank" do
      Shipping::StartReturn.call(order: @order, reason: "   ")

      assert_nil @order.reload.return_reason
    end

    test "a refused return records no reason" do
      result = Shipping::StartReturn.call(order: orders(:producing), reason: "não deveria salvar")

      assert_not result.success?
      assert_nil orders(:producing).reload.return_reason
    end
  end
end
