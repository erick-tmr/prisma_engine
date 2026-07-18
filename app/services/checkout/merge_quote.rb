module Checkout
  class MergeQuote
    SERVICE_TIERS = { "mini_envios" => 0, "pac" => 1, "sedex" => 2 }.freeze

    Result = Data.define(
      :master, :absorbed_orders, :combined_weight_grams, :service, :service_label,
      :combined_shipping_cents, :paid_fretes_cents, :delta_cents,
      :subtotal_cents, :amount_cents, :savings_cents, :business_days, :error
    ) do
      def eligible?
        error.nil?
      end

      def all_order_ids
        [ master.id, *absorbed_orders.map(&:id) ]
      end
    end

    def self.call(user:, cart:)
      new(user: user, cart: cart).call
    end

    def initialize(user:, cart:)
      @user = user
      @cart = cart
    end

    def call
      orders = user.orders.mergeable.includes(:shipment).to_a
      return failure(:no_mergeable) if orders.empty?

      service = choose_service(orders)
      return failure(:shipping_unavailable) unless service

      build(orders, service)
    rescue Correios::Api::Error
      failure(:shipping_error)
    end

    private

    attr_reader :user, :cart

    def failure(error)
      Result.new(
        master: nil, absorbed_orders: [], combined_weight_grams: nil, service: nil,
        service_label: nil, combined_shipping_cents: nil, paid_fretes_cents: nil,
        delta_cents: nil, subtotal_cents: cart.subtotal_cents, amount_cents: nil,
        savings_cents: nil, business_days: nil, error: error
      )
    end

    def build(orders, service)
      master   = orders.first
      paid     = orders.sum { |order| order.shipment.shipping_cents }
      combined = service[:price_cents]
      delta    = [ combined - master.shipment.shipping_cents, 0 ].max

      Result.new(
        master:                  master,
        absorbed_orders:         orders.drop(1),
        combined_weight_grams:   combined_weight(orders),
        service:                 service[:key].to_s,
        service_label:           service[:label],
        combined_shipping_cents: combined,
        paid_fretes_cents:       paid,
        delta_cents:             delta,
        subtotal_cents:          cart.subtotal_cents,
        amount_cents:            cart.subtotal_cents + delta,
        savings_cents:           savings(orders, paid, combined),
        business_days:           service[:business_days],
        error:                   nil
      )
    end

    def choose_service(orders)
      floor = orders.map { |order| SERVICE_TIERS.fetch(order.shipment.service, 0) }.max
      allowed = quote(orders, combined_weight(orders)).select do |service|
        service[:eligible] && SERVICE_TIERS.fetch(service[:key].to_s, 0) >= floor
      end
      allowed.min_by { |service| service[:price_cents] }
    end

    def savings(orders, paid, combined)
      alone    = cheapest(quote(orders, Shipping::PackageWeight.call(cart)))&.dig(:price_cents)
      baseline = alone ? paid + alone : paid
      [ baseline - combined, 0 ].max
    end

    def quote(orders, weight)
      Shipping::Quote.call(cep_destino: orders.first.shipment.zip, weight_grams: weight)
    end

    def cheapest(services)
      services.select { |service| service[:eligible] }.min_by { |service| service[:price_cents] }
    end

    def combined_weight(orders)
      @combined_weight ||= Shipping::CombinedWeight.call(orders: orders, cart: cart)
    end
  end
end
