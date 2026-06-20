module Checkout
  class PlaceOrder
    Result = Data.define(:order, :error) do
      def success?
        error.nil?
      end
    end

    def self.call(user:, cart:, address_id:, shipping_service:)
      new(user: user, cart: cart, address_id: address_id, shipping_service: shipping_service).call
    end

    def initialize(user:, cart:, address_id:, shipping_service:)
      @user             = user
      @cart             = cart
      @address_id       = address_id
      @shipping_service = shipping_service.to_s
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

    attr_reader :user, :cart, :address_id, :shipping_service

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
          order_items_attributes: cart.lines.map { |line| item_attributes(line) }
        )
        order.create_shipment!(shipment_attributes(address, shipping))
        order
      end
    end

    def shipment_attributes(address, shipping)
      {
        service:        shipping_service,
        shipping_cents: shipping,
        weight_grams:   package_weight,
        height_cm:      Shipping::PACKAGE_DIMENSIONS[:altura_cm],
        width_cm:       Shipping::PACKAGE_DIMENSIONS[:largura_cm],
        length_cm:      Shipping::PACKAGE_DIMENSIONS[:comprimento_cm],
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

    def item_attributes(line)
      product = line.product
      {
        product_id:       product.id,
        name:             product.title,
        unit_price_cents: line.unit_price_cents,
        quantity:         line.quantity,
        chosen_options:   line.options.map { |opt| opt.group_name.present? ? "#{opt.group_name}: #{opt.name}" : opt.name },
        photo_path:       product.image
      }
    end
  end
end
