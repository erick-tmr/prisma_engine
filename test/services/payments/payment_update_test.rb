require "test_helper"

module Payments
  class PaymentUpdateTest < ActiveSupport::TestCase
    include ActionMailer::TestHelper

    setup do
      @order = Order.create!(
        user: users(:confirmed),
        subtotal_cents: 18_000, total_cents: 19_984,
      )
    end

    def payload(overrides = {})
      {
        "order_nsu"       => @order.number,
        "paid_amount"     => @order.total_cents,
        "transaction_nsu" => "tx-abc",
        "receipt_url"     => "https://recibo.infinitepay.io/tx-abc",
        "capture_method"  => "pix"
      }.merge(overrides)
    end

    def call(overrides = {})
      Payments::PaymentUpdate.call(order: @order, payload: payload(overrides))
    end

    test "confirms an awaiting_payment order and records the payment fields" do
      assert_enqueued_email_with OrderMailer, :payment_confirmed, args: [ @order ] do
        call
      end
      @order.reload
      assert @order.payment_confirmed?
      assert_equal "tx-abc", @order.external_id
      assert_equal "https://recibo.infinitepay.io/tx-abc", @order.receipt_url
      assert_equal "pix", @order.payment_method
    end

    test "reopens and confirms a cancelled order" do
      @order.cancel!
      call
      assert @order.reload.payment_confirmed?
    end

    test "is a no-op when the order is already payment_confirmed" do
      @order.confirm_payment!
      @order.update!(external_id: "prior-tx")
      call
      @order.reload
      assert @order.payment_confirmed?
      assert_equal "prior-tx", @order.external_id
    end

    test "is a no-op for an order already in fulfillment" do
      @order.confirm_payment!
      @order.transition_to!("in_production")
      assert_nothing_raised { call }
      assert @order.reload.in_production?
    end

    test "skips and does not confirm when order_nsu does not match" do
      call("order_nsu" => "PG-000000000000")
      assert @order.reload.awaiting_payment?
    end

    test "skips when paid_amount is below the order total" do
      call("paid_amount" => @order.total_cents - 1)
      assert @order.reload.awaiting_payment?
    end

    test "confirms when paid_amount exceeds the order total (installment interest)" do
      call("paid_amount" => @order.total_cents + 3_173)
      assert @order.reload.payment_confirmed?
    end

    test "confirms cleanly when the redirect already recorded the same transaction_nsu" do
      @order.update!(external_id: "tx-abc")
      call
      assert @order.reload.payment_confirmed?
    end
  end
end
