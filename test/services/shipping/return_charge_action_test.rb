require "test_helper"

module Shipping
  class ReturnChargeActionTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper
    include ActionMailer::TestHelper

    setup do
      stub_return_quote
      @order = orders(:delivered)
      Shipping::StartReturn.call(order: @order, payer: "customer")
      @order.reload
      @shipment = @order.return_shipment
      @charge = @shipment.freight_charge
    end

    test "assuming the freight voids the charge and starts the label" do
      assert_enqueued_with(job: Shipping::CreatePrePostagemJob) do
        assert Shipping::AssumeReturnFreight.call(order: @order).success?
      end

      assert @charge.reload.voided_at
      assert_nil @shipment.freight_charge
      assert @shipment.freight_settled?
    end

    test "an expired charge can be assumed too" do
      @charge.update!(expires_at: 1.minute.ago)

      assert Shipping::AssumeReturnFreight.call(order: @order).success?
      assert @charge.reload.voided_at
    end

    test "a paid charge cannot be assumed" do
      @charge.update!(paid_at: Time.current)

      result = Shipping::AssumeReturnFreight.call(order: @order)

      assert_equal :no_charge, result.error
      assert_nil @charge.reload.voided_at
    end

    test "assuming twice loses the second time rather than buying a second label" do
      Shipping::AssumeReturnFreight.call(order: @order)

      assert_equal :no_charge, Shipping::AssumeReturnFreight.call(order: @order.reload).error
    end

    test "nothing to act on once the order has left awaiting_return" do
      @order.transition_to!("returning", automatic: true)

      assert_equal :not_awaiting, Shipping::AssumeReturnFreight.call(order: @order).error
      assert_equal :not_awaiting, Shipping::ResendReturnCharge.call(order: @order).error
      assert_equal :not_awaiting, Shipping::RenewReturnCharge.call(order: @order).error
    end

    test "once the store pays there is no charge left to resend" do
      @charge.update!(voided_at: Time.current)

      assert_equal :no_charge, Shipping::ResendReturnCharge.call(order: @order).error
    end

    test "resending mails the pending charge again" do
      assert_enqueued_email_with OrderMailer, :awaiting_return, args: [ @order ] do
        assert Shipping::ResendReturnCharge.call(order: @order).success?
      end
    end

    test "an expired charge is renewed, not resent" do
      @charge.update!(expires_at: 1.minute.ago)

      assert_equal :no_charge, Shipping::ResendReturnCharge.call(order: @order).error
    end

    test "renewing an expired charge issues a fresh link for the same amount and mails it" do
      @charge.update!(expires_at: 1.minute.ago)

      freeze_time do
        assert_enqueued_email_with OrderMailer, :awaiting_return, args: [ @order ] do
          assert Shipping::RenewReturnCharge.call(order: @order).success?
        end

        renewed = @shipment.freight_charge
        assert_not_equal @charge, renewed
        assert_equal @charge.amount_cents, renewed.amount_cents
        assert_equal ReturnFreightCharge::TTL.from_now, renewed.expires_at
      end
    end

    test "a charge still within its window is not renewed" do
      assert_no_difference -> { ReturnFreightCharge.count } do
        assert_equal :no_charge, Shipping::RenewReturnCharge.call(order: @order).error
      end
    end

    test "an order parked in awaiting_return with no return shipment has no charge" do
      order = orders(:producing)
      order.update_column(:status, "awaiting_return")

      assert_equal :no_charge, Shipping::ResendReturnCharge.call(order: order).error
    end
  end
end
