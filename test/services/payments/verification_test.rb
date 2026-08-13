require "test_helper"

module Payments
  class VerificationTest < ActiveSupport::TestCase
    URL = "#{InfinitePay::Api::BASE_URL}/payment_check".freeze

    setup do
      @order = Order.create!(user: users(:confirmed), subtotal_cents: 18_000, total_cents: 19_984)
    end

    def stub_check(overrides = {})
      body = { "success" => true, "paid" => true, "paid_amount" => @order.total_cents, "capture_method" => "pix" }
      stub_request(:post, URL).to_return(
        status: 200, body: body.merge(overrides).to_json, headers: { "Content-Type" => "application/json" }
      )
    end

    def verify(overrides = {})
      payload = {
        "order_nsu" => @order.number, "paid_amount" => @order.total_cents,
        "transaction_nsu" => "tx-abc", "invoice_slug" => "uXnT2kndIV",
        "receipt_url" => "https://recibo.infinitepay.io/tx-abc", "capture_method" => "pix"
      }
      Payments::Verification.call(order: @order, payload: payload.merge(overrides))
    end

    test "answers with infinitepay's figures rather than the ones the delivery claims" do
      stub_check("paid_amount" => 21_500, "capture_method" => "credit_card")

      result = verify("paid_amount" => 999_999, "capture_method" => "pix")

      assert result.verified?
      assert_equal 21_500, result.payload["paid_amount"]
      assert_equal "credit_card", result.payload["capture_method"]
      assert_equal @order.number, result.payload["order_nsu"]
      assert_equal "tx-abc", result.payload["transaction_nsu"]
      assert_equal "uXnT2kndIV", result.payload["invoice_slug"]
      assert_equal "https://recibo.infinitepay.io/tx-abc", result.payload["receipt_url"]
    end

    test "looks the transaction up under our own order number" do
      stub_check

      verify("order_nsu" => @order.number)

      assert_requested(:post, URL) do |req|
        assert_equal @order.number, JSON.parse(req.body)["order_nsu"]
        true
      end
    end

    test "an unpaid transaction is retryable rather than verified" do
      stub_check("paid" => false)

      result = verify

      assert_not result.verified?
      assert result.retryable
    end

    test "a transaction infinitepay does not recognize is rejected for good" do
      stub_check("success" => false, "paid" => false)

      result = verify

      assert_not result.verified?
      assert_not result.retryable
    end

    test "a delivery carrying no invoice_slug is rejected without asking infinitepay" do
      assert_not verify("invoice_slug" => nil).verified?
      assert_not_requested(:post, URL)
    end

    test "a delivery carrying no transaction_nsu is rejected without asking infinitepay" do
      assert_not verify("transaction_nsu" => "").verified?
      assert_not_requested(:post, URL)
    end

    test "a mismatched order_nsu is rejected without asking infinitepay" do
      assert_not verify("order_nsu" => "PG-00000").verified?
      assert_not_requested(:post, URL)
    end

    test "an order already past payment is rejected without asking infinitepay" do
      @order.confirm_payment!

      assert_not verify.verified?
      assert_not_requested(:post, URL)
    end

    test "a cancelled order can still be reopened by a verified payment" do
      @order.cancel!
      stub_check

      assert verify.verified?
    end

    test "names the order and the reason in the log when it rejects" do
      sink = StringIO.new
      original = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(sink)

      verify("invoice_slug" => nil)

      assert_match(/\[Payments::Verification\] order=#{@order.number} .*invoice_slug/, sink.string)
    ensure
      Rails.logger = original
    end
  end
end
