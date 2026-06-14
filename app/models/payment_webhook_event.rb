class PaymentWebhookEvent < ApplicationRecord
  belongs_to :order
end
