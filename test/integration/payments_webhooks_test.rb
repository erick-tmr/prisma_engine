require "test_helper"

class PaymentsWebhooksTest < ActionDispatch::IntegrationTest
  setup do
    @order = Order.create!(
      user: users(:confirmed),
      subtotal_cents: 18_000, shipping_cents: 1_984, total_cents: 19_984,
      shipping_service: "sedex",
      ship_receiver_name: "Cliente Confirmado", ship_receiver_cpf: "52998224725",
      ship_zip: "01310100", ship_street: "Av. Paulista", ship_number: "1578",
      ship_neighborhood: "Bela Vista", ship_city: "São Paulo", ship_state: "SP"
    )
  end

  def webhook(token, body)
    post payments_webhook_path(token), params: body.to_json, headers: { "Content-Type" => "application/json" }
  end

  def paid_payload(overrides = {})
    {
      "order_nsu" => @order.number, "paid_amount" => @order.total_cents,
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

  test "captures the raw payload to disk" do
    slug = "slug-#{SecureRandom.hex(6)}"
    webhook(@order.webhook_token, paid_payload("invoice_slug" => slug))

    assert_response :ok
    line = File.readlines(Payments::WebhookCapture.path).find { |entry| entry.include?(slug) }
    assert line, "expected a captured webhook line containing #{slug}"
    captured = JSON.parse(line)
    assert_equal slug, JSON.parse(captured["body"])["invoice_slug"]
    assert captured["received_at"].present?
  end

  test "an unknown token is rejected with 401 and confirms nothing" do
    webhook("nope-#{SecureRandom.hex(4)}", paid_payload)

    assert_response :unauthorized
    assert @order.reload.awaiting_payment?
  end

  test "a replayed webhook is an idempotent no-op" do
    body = paid_payload("transaction_nsu" => "tx-once")
    webhook(@order.webhook_token, body)
    webhook(@order.webhook_token, body)

    assert_response :ok
    @order.reload
    assert @order.payment_confirmed?
    assert_equal "tx-once", @order.external_id
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
