require "test_helper"

module Shipping
  class LegTest < ActiveSupport::TestCase
    setup do
      @order = orders(:delivered)
      @outbound = @order.shipment
      @inbound = Shipment.create!(order: @order, direction: :inbound, service: "pac")
    end

    test "picks the leg from the shipment direction" do
      assert_equal Shipping::Leg::OUTBOUND, Shipping::Leg.for(@outbound)
      assert_equal Shipping::Leg::INBOUND, Shipping::Leg.for(@inbound)
    end

    test "the outbound emittable set is exactly the shippable? guard it replaced" do
      Order::STATUSES.each do |status|
        expected = status != "cancelled"
        assert_equal expected, Shipping::Leg::OUTBOUND.emittable_statuses.include?(status), status
      end
    end

    test "the inbound leg only emits while the customer still holds the package" do
      assert Shipping::Leg::INBOUND.emittable_statuses.include?("awaiting_return")
      assert Shipping::Leg::INBOUND.emittable_statuses.include?("returning")
      assert_not Shipping::Leg::INBOUND.emittable_statuses.include?("returned")
    end

    test "outbound announces the label on the order and inbound stays quiet" do
      order = orders(:producing)

      Shipping::Leg::OUTBOUND.announce_label(order)
      assert order.reload.label_issued?

      returning = orders(:delivered)
      returning.transition_to!("awaiting_return", automatic: true)
      Shipping::Leg::INBOUND.announce_label(returning)
      assert returning.reload.awaiting_return?
    end

    test "the parties swap so the customer sends the return" do
      store = { nome: "Prisma Games" }
      customer = { nome: "Cliente" }

      assert_equal({ sender: store, recipient: customer }, Shipping::Leg::OUTBOUND.parties(store: store, customer: customer))
      assert_equal({ sender: customer, recipient: store }, Shipping::Leg::INBOUND.parties(store: store, customer: customer))
    end

    test "the return label carries the order number plus a marker" do
      assert_equal @order.number, Shipping::Leg::OUTBOUND.observacao_for(@order)
      assert_equal "#{@order.number} DEVOLUCAO", Shipping::Leg::INBOUND.observacao_for(@order)
    end
  end
end
