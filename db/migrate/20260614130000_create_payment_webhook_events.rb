class CreatePaymentWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_webhook_events do |t|
      t.references :order, null: false, foreign_key: true
      t.jsonb :headers, null: false, default: {}
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end
  end
end
