class OrderMailer < ApplicationMailer
  helper AccountHelper

  def payment_confirmed(order)
    deliver_for(order)
  end

  def label_issued(order)
    deliver_for(order)
  end

  def shipped(order)
    deliver_for(order)
  end

  def delivered(order)
    deliver_for(order)
  end

  def delivery_issue(order)
    @order = order
    @issue = Shipping::DeliveryIssue.for(order.shipment)
    @issue_url = issue_url
    mail(to: order.user.email,
         subject: t("order_mailer.delivery_issue.#{@issue.kind}.subject", number: order.number))
  end

  private

  def issue_url
    return @order.shipment.tracking_url if @issue.contact == :correios

    "mailto:#{t('mailer.support_email')}"
  end

  def deliver_for(order)
    @order = order
    mail(to: order.user.email, subject: default_i18n_subject(number: order.number))
  end
end
