module Payments
  class Checkout
    def self.start(order, redirect_url:, webhook_url:)
      new(order, redirect_url: redirect_url, webhook_url: webhook_url).start
    end

    def initialize(order, redirect_url:, webhook_url:)
      @order        = order
      @redirect_url = redirect_url
      @webhook_url  = webhook_url
    end

    def start
      InfinitePay::Api::Checkout.create(payload)
    rescue InfinitePay::Api::Error => error
      Rails.logger.error("[Payments::Checkout] order=#{order.number} link rejected: #{error.message}")
      raise
    end

    private

    attr_reader :order, :redirect_url, :webhook_url

    def payload
      {
        handle:       InfinitePay::Api::HANDLE,
        order_nsu:    order.number,
        items:        line_items,
        customer:     customer,
        address:      address,
        redirect_url: redirect_url,
        webhook_url:  webhook_url
      }
    end

    def line_items
      items = order.order_items.map do |item|
        { description: item.name, quantity: item.quantity, price: item.unit_price_cents }
      end
      return items unless shipment.shipping_cents.positive?

      items << { description: "Frete: #{shipment.service}", quantity: 1, price: shipment.shipping_cents }
    end

    def customer
      base  = { name: order.user.full_name, email: order.user.email }
      phone = Phones.e164(order.user.phone)
      return base unless phone

      base.merge(phone_number: phone)
    end

    def address
      {
        cep:          shipment.zip,
        street:       shipment.street,
        neighborhood: shipment.neighborhood,
        number:       shipment.number,
        complement:   shipment.complement
      }
    end

    def shipment
      order.shipment
    end
  end
end
