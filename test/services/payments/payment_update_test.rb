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

    test "executes a pending merge once the carrier payment confirms" do
      master, carrier, plan = build_merge_scenario

      assert_no_enqueued_emails do
        Payments::PaymentUpdate.call(order: carrier, payload: carrier_payload(carrier))
      end

      assert carrier.reload.merged?
      assert_equal master, carrier.merged_into
      assert plan.reload.executed_at.present?
      assert_equal 2, master.reload.order_items.count
    end

    test "a duplicate webhook does not merge twice" do
      _master, carrier, _plan = build_merge_scenario
      2.times { Payments::PaymentUpdate.call(order: carrier, payload: carrier_payload(carrier)) }
      assert_equal 1, carrier.reload.merged_into.order_items.where.not(name: "Item master").count
    end

    def build_merge_scenario
      master = @order.user.orders.create!(subtotal_cents: 10_000, total_cents: 12_990, status: "payment_confirmed")
      master.order_items.create!(name: "Item master", unit_price_cents: 10_000, quantity: 1)
      master.create_shipment!(shipment_attrs(2_990))

      carrier = @order.user.orders.create!(subtotal_cents: 3_000, total_cents: 4_184, status: "awaiting_payment")
      carrier.order_items.create!(name: "Item novo", unit_price_cents: 3_000, quantity: 1)
      carrier.create_shipment!(shipment_attrs(1_184))
      plan = OrderMerge.create!(
        carrier_order: carrier, master_order: master, absorbed_order_ids: [],
        combined_weight_grams: 400, combined_service: "pac",
        combined_shipping_cents: 3_500, paid_fretes_cents: 2_990
      )
      [ master, carrier, plan ]
    end

    def carrier_payload(carrier)
      payload("order_nsu" => carrier.number, "paid_amount" => carrier.total_cents)
    end

    def shipment_attrs(frete)
      {
        service: "pac", shipping_cents: frete, weight_grams: 250,
        height_cm: 4, width_cm: 16, length_cm: 24,
        receiver_name: "Master", receiver_cpf: "39053344705", zip: "04534003",
        street: "Rua", number: "1", neighborhood: "Itaim", city: "São Paulo", state: "SP"
      }
    end
  end
end
