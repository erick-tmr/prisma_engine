class CheckoutController < ApplicationController
  before_action :authenticate_user!

  layout "checkout"

  ERROR_MESSAGES = {
    empty_cart:           "Seu carrinho está vazio.",
    invalid_address:      "Selecione um endereço de entrega válido.",
    shipping_unavailable: "A forma de envio escolhida não está disponível. Escolha outra.",
    shipping_error:       "Não foi possível calcular o frete agora. Tente novamente em instantes."
  }.freeze

  def show
    @cart = current_cart
    persist_cart_if_cleaned
    return redirect_to cart_path, notice: ERROR_MESSAGES[:empty_cart] if @cart.empty?

    @addresses = current_user.addresses.default_first
    chosen_id  = session.delete("checkout_address_id").to_i
    @selected_address = @addresses.find { |addr| addr.id == chosen_id } || @addresses.first
    @selected_shipping_service = session["checkout_shipping_service"]
  end

  def create
    result = Checkout::PlaceOrder.call(
      user: current_user, cart: current_cart,
      address_id: params[:address_id], shipping_service: params[:shipping_service]
    )

    if result.success?
      clear_cart!
      flash[:notice] = "Pedido #{result.order.number} criado."
      redirect_to root_path
    else
      flash[:alert] = ERROR_MESSAGES.fetch(result.error)
      redirect_to checkout_path
    end
  end

  def create_address
    address = current_user.addresses.build(address_params)
    if address.save
      session["checkout_address_id"] = address.id
      redirect_to checkout_path
    else
      flash[:alert] = address.errors.full_messages.to_sentence
      redirect_to checkout_path
    end
  end

  private

  def persist_cart_if_cleaned
    cookies.signed[:cart] = { value: @cart.to_cookie, expires: 30.days.from_now } if @cart.cleanup!
  end

  def clear_cart!
    cookies.delete(:cart)
    session.delete("checkout_shipping_service")
  end

  def address_params
    params.expect(address: %i[zip street number complement neighborhood city state receiver_name receiver_cpf])
  end
end
