module Payments
  module WebhookCapture
    module_function

    def record(headers:, body:)
      File.open(path, "a") do |file|
        file.puts({ received_at: Time.current.utc.iso8601, headers: headers, body: body }.to_json)
      end
    end

    def path
      Rails.root.join("log", "infinitepay_webhooks.#{Rails.env}.jsonl")
    end
  end
end
