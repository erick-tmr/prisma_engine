module Checkout
  class PlaceMergeOrder
    Result = Data.define(:order, :error) do
      def success?
        error.nil?
      end
    end

    def self.call(user:, cart:, observation: nil, receiver_obs: nil)
      new(user: user, cart: cart, observation: observation, receiver_obs: receiver_obs).call
    end

    def initialize(user:, cart:, observation: nil, receiver_obs: nil)
      @user         = user
      @cart         = cart
      @observation  = observation
      @receiver_obs = receiver_obs
    end

    def call
      cart.cleanup!
      return failure(:empty_cart) if cart.empty?

      quote = MergeQuote.call(user: user, cart: cart)
      return failure(quote.error) unless quote.eligible?

      Result.new(order: build_carrier(quote), error: nil)
    end

    private

    attr_reader :user, :cart, :observation, :receiver_obs

    def failure(error)
      Result.new(order: nil, error: error)
    end

    def build_carrier(quote)
      Order.transaction do
        carrier = Order.create!(
          user:                   user,
          subtotal_cents:         quote.subtotal_cents,
          total_cents:            quote.amount_cents,
          observation:            observation,
          order_items_attributes: cart.lines.map { |line| CartItems.attributes_for(line) }
        )
        carrier.create_shipment!(shipment_attributes(quote))
        create_plan(carrier, quote)
        carrier
      end
    end

    def shipment_attributes(quote)
      {
        service:                quote.service,
        shipping_cents:         quote.delta_cents,
        delivery_business_days: quote.business_days,
        weight_grams:           Shipping::PackageWeight.call(cart),
        height_cm:              Shipping::PACKAGE_DIMENSIONS[:altura_cm],
        width_cm:               Shipping::PACKAGE_DIMENSIONS[:largura_cm],
        length_cm:              Shipping::PACKAGE_DIMENSIONS[:comprimento_cm],
        receiver_obs:           receiver_obs,
        **address_snapshot(quote.master.shipment)
      }
    end

    def address_snapshot(shipment)
      {
        receiver_name: shipment.receiver_name,
        receiver_cpf:  shipment.receiver_cpf,
        zip:           shipment.zip,
        street:        shipment.street,
        number:        shipment.number,
        complement:    shipment.complement,
        neighborhood:  shipment.neighborhood,
        city:          shipment.city,
        state:         shipment.state
      }
    end

    def create_plan(carrier, quote)
      OrderMerge.create!(
        carrier_order:           carrier,
        master_order:            quote.master,
        absorbed_order_ids:      quote.absorbed_orders.map(&:id),
        combined_weight_grams:   quote.combined_weight_grams,
        combined_service:        quote.service,
        combined_shipping_cents: quote.combined_shipping_cents,
        paid_fretes_cents:       quote.paid_fretes_cents
      )
    end
  end
end
