module Checkout
  class PlaceOrder
    Result = Data.define(:order, :error) do
      def success?
        error.nil?
      end
    end

    def self.call(user:, cart:, address_id:, shipping_service:, observation: nil, receiver_obs: nil)
      new(
        user: user, cart: cart, address_id: address_id, shipping_service: shipping_service,
        observation: observation, receiver_obs: receiver_obs
      ).call
    end

    def initialize(user:, cart:, address_id:, shipping_service:, observation: nil, receiver_obs: nil)
      @user             = user
      @cart             = cart
      @address_id       = address_id
      @shipping_service = shipping_service.to_s
      @observation      = observation
      @receiver_obs     = receiver_obs
    end

    def call
      cart.cleanup!
      return failure(:empty_cart) if cart.empty?

      address = user.addresses.find_by(id: address_id)
      return failure(:invalid_address) unless address

      service = eligible_service(address)
      return failure(:shipping_unavailable) unless service

      Result.new(order: build_order(address, service), error: nil)
    rescue Correios::Api::Error
      failure(:shipping_error)
    end

    private

    attr_reader :user, :cart, :address_id, :shipping_service, :observation, :receiver_obs

    def failure(error)
      Result.new(order: nil, error: error)
    end

    def package_weight
      @package_weight ||= Shipping::PackageWeight.call(cart)
    end

    def eligible_service(address)
      quote = Shipping::Quote.call(cep_destino: address.zip, weight_grams: package_weight)
      quote.find { |service| service[:key].to_s == shipping_service && service[:eligible] }
    end

    def build_order(address, service)
      subtotal = cart.subtotal_cents
      shipping = service[:price_cents]
      Order.transaction do
        order = Order.create!(
          user:                   user,
          subtotal_cents:         subtotal,
          total_cents:            subtotal + shipping,
          observation:            observation,
          order_items_attributes: cart.lines.map { |line| Checkout::CartItems.attributes_for(line) }
        )
        order.create_shipment!(shipment_attributes(address, service))
        order
      end
    end

    def shipment_attributes(address, service)
      {
        service:                shipping_service,
        shipping_cents:         service[:price_cents],
        delivery_business_days: service[:business_days],
        weight_grams:           package_weight,
        height_cm:              Shipping::PACKAGE_DIMENSIONS[:altura_cm],
        width_cm:               Shipping::PACKAGE_DIMENSIONS[:largura_cm],
        length_cm:              Shipping::PACKAGE_DIMENSIONS[:comprimento_cm],
        receiver_obs:           receiver_obs,
        **address_snapshot(address)
      }
    end

    def address_snapshot(address)
      {
        receiver_name: address.receiver_name,
        receiver_cpf:  address.receiver_cpf,
        zip:           address.zip,
        street:        address.street,
        number:        address.number,
        complement:    address.complement,
        neighborhood:  address.neighborhood,
        city:          address.city,
        state:         address.state
      }
    end
  end
end
