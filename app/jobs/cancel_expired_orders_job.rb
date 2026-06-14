class CancelExpiredOrdersJob < ApplicationJob
  def perform
    Order.awaiting_payment_expired.find_each(&:cancel!)
  end
end
