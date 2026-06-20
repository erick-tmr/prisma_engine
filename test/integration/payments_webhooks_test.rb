require "test_helper"

class PaymentsWebhooksTest < ActionDispatch::IntegrationTest
  setup do
    @order = Order.create!(
      user: users(:confirmed),
      subtotal_cents: 18_000, total_cents: 19_984,
    )
  end

  def webhook(token, body)
    post payments_webhook_path(token), params: body.to_json, headers: { "Content-Type" => "application/json" }
  end

  def paid_payload(overrides = {})
    {
      "order_nsu" => @order.number, "paid_amount" => @order.subtotal_cents,
      "transaction_nsu" => "tx-#{SecureRandom.hex(6)}",
      "receipt_url" => "https://recibo.infinitepay.io/tx", "capture_method" => "pix"
    }.merge(overrides)
  end

  test "a valid token with a matching paid payload confirms the order and answers 200" do
    webhook(@order.webhook_token, paid_payload("transaction_nsu" => "tx-confirm"))

    assert_response :ok
    @order.reload
    assert @order.payment_confirmed?
    assert_equal "tx-confirm", @order.external_id
  end

  test "captures the webhook to the database for auditing" do
    webhook(@order.webhook_token, paid_payload("invoice_slug" => "uXnT2kndIV"))

    assert_response :ok
    event = @order.payment_webhook_events.last
    assert_not_nil event
    assert_equal "uXnT2kndIV", event.payload["invoice_slug"]
    assert event.headers["CONTENT_TYPE"].present?
  end

  test "an unknown token is rejected with 401 and captures + confirms nothing" do
    assert_no_difference "PaymentWebhookEvent.count" do
      webhook("nope-#{SecureRandom.hex(4)}", paid_payload)
    end

    assert_response :unauthorized
    assert @order.reload.awaiting_payment?
  end

  test "a replayed webhook is an idempotent no-op but still captures each delivery" do
    body = paid_payload("transaction_nsu" => "tx-once")
    webhook(@order.webhook_token, body)
    webhook(@order.webhook_token, body)

    assert_response :ok
    @order.reload
    assert @order.payment_confirmed?
    assert_equal "tx-once", @order.external_id
    assert_equal 2, @order.payment_webhook_events.count
  end

  test "a mismatched amount answers 200 but leaves the order awaiting payment" do
    webhook(@order.webhook_token, paid_payload("paid_amount" => 1))

    assert_response :ok
    assert @order.reload.awaiting_payment?
  end

  test "a mismatched order_nsu answers 200 but leaves the order awaiting payment" do
    webhook(@order.webhook_token, paid_payload("order_nsu" => "PG-000000000000"))

    assert_response :ok
    assert @order.reload.awaiting_payment?
  end

  test "a valid token with an empty body is a 200 no-op" do
    webhook(@order.webhook_token, {})

    assert_response :ok
    assert @order.reload.awaiting_payment?
  end
end
