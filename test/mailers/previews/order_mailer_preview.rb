class OrderMailerPreview < ActionMailer::Preview
  def payment_confirmed
    OrderMailer.payment_confirmed(Order.paid.recent_first.first || Order.first)
  end

  def label_issued
    OrderMailer.label_issued(shipped_order)
  end

  def shipped
    OrderMailer.shipped(shipped_order)
  end

  def delivered
    OrderMailer.delivered(shipped_order)
  end

  def delivery_issue
    OrderMailer.delivery_issue(shipped_order)
  end

  private

  def shipped_order
    tracked = Order.joins(:shipment)
                   .where.not(shipments: { tracking_code: nil })
                   .where.not(shipments: { delivery_business_days: nil })
    tracked.recent_first.first || Order.joins(:shipment).recent_first.first || Order.first
  end
end
