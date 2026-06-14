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
    end

    private

    attr_reader :order, :redirect_url, :webhook_url

    def payload
      {
        handle:       ENV.fetch("INFINITEPAY_HANDLE"),
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
      items << { description: "Frete — #{order.shipping_service}", quantity: 1, price: order.shipping_cents }
      items
    end

    def customer
      base  = { name: order.user.full_name, email: order.user.email }
      phone = Phones.e164(order.user.phone)
      return base unless phone

      base.merge(phone_number: phone)
    end

    def address
      {
        cep:          order.ship_zip,
        street:       order.ship_street,
        neighborhood: order.ship_neighborhood,
        number:       order.ship_number,
        complement:   order.ship_complement
      }
    end
  end
end
