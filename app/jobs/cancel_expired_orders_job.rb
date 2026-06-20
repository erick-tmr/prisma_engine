class CancelExpiredOrdersJob < ApplicationJob
  def perform
    Order.awaiting_payment_expired.find_each { |order| order.cancel!(automatic: true) }
  end
end
