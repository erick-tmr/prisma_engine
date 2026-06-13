require "test_helper"

class PaymentsWebhooksTest < ActionDispatch::IntegrationTest
  test "captures the raw payload to disk and answers 200" do
    slug = "slug-#{SecureRandom.hex(6)}"
    payload = { "invoice_slug" => slug, "order_nsu" => "PG-202606130001", "capture_method" => "pix" }

    post payments_webhook_path, params: payload.to_json, headers: { "Content-Type" => "application/json" }

    assert_response :ok
    line = File.readlines(Payments::WebhookCapture.path).find { |entry| entry.include?(slug) }
    assert line, "expected a captured webhook line containing #{slug}"
    captured = JSON.parse(line)
    assert_equal payload, JSON.parse(captured["body"])
    assert captured["received_at"].present?
  end

  test "does not require a CSRF token or authentication" do
    post payments_webhook_path, params: "{}", headers: { "Content-Type" => "application/json" }
    assert_response :ok
  end
end
