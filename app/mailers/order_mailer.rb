class OrderMailer < ApplicationMailer
  helper AccountHelper

  ISSUE_HEROES = {
    awaiting_pickup: "dragon-letter-full.png",
    unknown: "dragon-face.png"
  }.freeze
  DEFAULT_ISSUE_HERO = "dragon-letter-full.png".freeze

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

  def returned(order)
    @whatsapp_url = whatsapp_url(order)
    deliver_for(order)
  end

  def delivery_issue(order)
    @order = order
    @issue = Shipping::DeliveryIssue.for(order.shipment)
    @hero = ISSUE_HEROES.fetch(@issue.kind, DEFAULT_ISSUE_HERO)
    mail(to: order.user.email,
         subject: t("order_mailer.delivery_issue.#{@issue.kind}.subject", number: order.number))
  end

  private

  def whatsapp_url(order)
    message = t("order_mailer.returned.whatsapp_message", number: order.number)

    "#{NavHelper::SOCIAL_LINKS.fetch(:whatsapp)}?text=#{CGI.escape(message)}"
  end

  def deliver_for(order)
    @order = order
    mail(to: order.user.email, subject: default_i18n_subject(number: order.number))
  end
end
