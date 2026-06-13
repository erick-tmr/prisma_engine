class CheckoutController < ApplicationController
  before_action :authenticate_user!

  layout "checkout"

  # Flash copy for each PlaceOrder failure. Kept here (like CartQuotesController's
  # INELIGIBLE_MESSAGES) so the customer-facing pt-BR strings live next to the action.
  ERROR_MESSAGES = {
    empty_cart:           "Seu carrinho está vazio.",
    invalid_address:      "Selecione um endereço de entrega válido.",
    shipping_unavailable: "A forma de envio escolhida não está disponível. Escolha outra.",
    shipping_error:       "Não foi possível calcular o frete agora. Tente novamente em instantes."
  }.freeze

  # Delivery + payment screen, wired to the real cart, the customer's saved
  # addresses, and a live Correios quote (the JS re-quotes cart_quote_path against
  # the selected address CEP). `@selected_shipping_service` is the option picked on
  # the cart (stashed by CartController#finalize) so the page opens on it.
  def show
    @cart = current_cart
    persist_cart_if_cleaned
    return redirect_to cart_path, notice: ERROR_MESSAGES[:empty_cart] if @cart.empty?

    @addresses = current_user.addresses.default_first
    chosen_id  = session.delete("checkout_address_id").to_i
    @selected_address = @addresses.find { |addr| addr.id == chosen_id } || @addresses.first
    @selected_shipping_service = session["checkout_shipping_service"]
  end

  # "Confirmar e pagar": create the order from the cookie cart, clear the cart, and
  # land on the home page. Redirecting home is the placeholder for the payment
  # hand-off — the InfinitePay hosted redirect replaces it when payment lands.
  def create
    result = Checkout::PlaceOrder.call(
      user: current_user, cart: current_cart,
      address_id: params[:address_id], shipping_service: params[:shipping_service]
    )

    if result.success?
      clear_cart!
      # Flash set separately so redirect_to only ever takes a static path helper
      # (keeps Semgrep's avoid-redirect rule from tainting the dynamic message).
      flash[:notice] = "Pedido #{result.order.number} criado."
      redirect_to root_path
    else
      flash[:alert] = ERROR_MESSAGES.fetch(result.error)
      redirect_to checkout_path
    end
  end

  # Inline "add new address" on the checkout. Persists a real Address, then returns
  # to checkout with it pre-selected; on validation failure, back to checkout with
  # the reason in the flash (the customer re-enters — rare, CPF/CEP format only).
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
