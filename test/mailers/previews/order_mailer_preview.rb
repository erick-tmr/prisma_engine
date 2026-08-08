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
    OrderMailer.delivery_issue(order_matching_issue(:catalogued) || shipped_order)
  end

  def delivery_issue_unknown
    OrderMailer.delivery_issue(order_matching_issue(:unknown) || shipped_order)
  end

  private

  def order_matching_issue(wanted)
    Order.joins(:shipment).where.not(shipments: { tracking_code: nil }).recent_first.find do |order|
      unknown = Shipping::DeliveryIssue.for(order.shipment).kind == Shipping::DeliveryIssue::UNKNOWN
      unknown == (wanted == :unknown)
    end
  end

  def shipped_order
    tracked = Order.joins(:shipment)
                   .where.not(shipments: { tracking_code: nil })
                   .where.not(shipments: { delivery_business_days: nil })
    tracked.recent_first.first || Order.joins(:shipment).recent_first.first || Order.first
  end
end
