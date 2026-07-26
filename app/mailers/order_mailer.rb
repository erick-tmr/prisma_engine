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
    deliver_for(order)
  end

  private

  def deliver_for(order)
    @order = order
    mail(to: order.user.email, subject: default_i18n_subject(number: order.number))
  end
end
