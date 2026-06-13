module Checkout
  # Turns the cookie cart plus the shopper's chosen address and shipping service
  # into a persisted Order, snapshotting prices / options / address so the order is
  # a frozen historical record (catalog or address edits can't mutate it later).
  #
  # Shipping is re-quoted from Correios server-side: the price and eligibility come
  # from a fresh quote against the address CEP, never from whatever the page
  # submitted (a hand-edited DOM could post any service code or price).
  #
  #   Checkout::PlaceOrder.call(user:, cart:, address_id:, shipping_service:)
  #     → Result(order:, error:)  # success? when error is nil
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

    # The chosen service, re-priced from a fresh Correios quote against the address
    # CEP and the same package weight the cart quote uses. nil when the service
    # code is unknown or Correios marks it ineligible for this parcel.
    def eligible_service(address)
      weight = Shipping::PackageWeight.call(cart)
      quote  = Shipping::Quote.call(cep_destino: address.zip, weight_grams: weight)
      quote.find { |service| service[:key].to_s == shipping_service && service[:eligible] }
    end

    def build_order(address, service)
      subtotal = cart.subtotal_cents
      shipping = service[:price_cents]
      Order.create!(
        user:             user,
        subtotal_cents:   subtotal,
        shipping_cents:   shipping,
        total_cents:      subtotal + shipping,
        shipping_service: shipping_service,
        order_items_attributes: cart.lines.map { |line| item_attributes(line) },
        **address_snapshot(address)
      )
    end

    def address_snapshot(address)
      {
        ship_receiver_name: address.receiver_name,
        ship_receiver_cpf:  address.receiver_cpf,
        ship_zip:           address.zip,
        ship_street:        address.street,
        ship_number:        address.number,
        ship_complement:    address.complement,
        ship_neighborhood:  address.neighborhood,
        ship_city:          address.city,
        ship_state:         address.state
      }
    end

    # :reek:FeatureEnvy — a builder: by construction it reads the line + product to
    # freeze their values onto the snapshot, it doesn't act on its own state.
    def item_attributes(line)
      product = line.product
      {
        product_id:       product.id,
        name:             product.title,
        unit_price_cents: line.unit_price_cents,
        quantity:         line.quantity,
        chosen_options:   line.options.map { |option| option_label(option) },
        photo_path:       product.image
      }
    end

    # :reek:UtilityFunction — pure formatting of one option for the snapshot;
    # mirrors the "Grupo: Nome" shape the account/Pedidos page already renders.
    def option_label(option)
      group = option.group_name
      group.present? ? "#{group}: #{option.name}" : option.name
    end
  end
end
