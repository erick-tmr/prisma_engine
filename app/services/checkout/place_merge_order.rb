module Checkout
  class PlaceMergeOrder
    Result = Data.define(:order, :payment_url, :error) do
      def success?
        error.nil?
      end
    end

    def self.call(user:, cart:, payment_link:, observation: nil, receiver_obs: nil)
      new(
        user: user, cart: cart, payment_link: payment_link,
        observation: observation, receiver_obs: receiver_obs
      ).call
    end

    def initialize(user:, cart:, payment_link:, observation: nil, receiver_obs: nil)
      @user         = user
      @cart         = cart
      @payment_link = payment_link
      @observation  = observation
      @receiver_obs = receiver_obs
    end

    def call
      cart.cleanup!
      return failure(:empty_cart) if cart.empty?

      quote = MergeQuote.call(user: user, cart: cart)
      return failure(quote.error) unless quote.eligible?

      place(build_carrier(quote))
    end

    private

    attr_reader :user, :cart, :payment_link, :observation, :receiver_obs

    def failure(error)
      Result.new(order: nil, payment_url: nil, error: error)
    end

    def place(carrier)
      payment_url = payment_link.call(carrier)
      carrier.save!
      Result.new(order: carrier, payment_url: payment_url, error: nil)
    rescue InfinitePay::Api::Error
      failure(:payment_error)
    end

    def build_carrier(quote)
      carrier = Order.new(
        user:                   user,
        subtotal_cents:         quote.subtotal_cents,
        total_cents:            quote.amount_cents,
        observation:            observation,
        order_items_attributes: cart.lines.map { |line| CartItems.attributes_for(line) }
      )
      carrier.build_shipment(shipment_attributes(quote))
      carrier.build_order_merge(plan_attributes(quote))
      carrier.assign_number
      carrier
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

    def plan_attributes(quote)
      {
        master_order:            quote.master,
        absorbed_order_ids:      quote.absorbed_orders.map(&:id),
        combined_weight_grams:   quote.combined_weight_grams,
        combined_service:        quote.service,
        combined_shipping_cents: quote.combined_shipping_cents,
        paid_fretes_cents:       quote.paid_fretes_cents
      }
    end
  end
end
