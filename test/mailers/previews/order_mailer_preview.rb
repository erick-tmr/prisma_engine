class OrderMailerPreview < ActionMailer::Preview
  def payment_confirmed
    OrderMailer.payment_confirmed(Order.first)
  end

  def delivered
    OrderMailer.delivered(shipped_order)
  end

  def delivery_issue
    OrderMailer.delivery_issue(shipped_order)
  end

  private

  def shipped_order
    Order.joins(:shipment).first || Order.first
  end
end
