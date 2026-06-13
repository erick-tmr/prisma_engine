# :reek:TooManyInstanceVariables
class CheckoutController < ApplicationController
  before_action :authenticate_user!

  layout "checkout"

  ERROR_MESSAGES = {
    empty_cart:           "Seu carrinho está vazio.",
    invalid_address:      "Selecione um endereço de entrega válido.",
    shipping_unavailable: "A forma de envio escolhida não está disponível. Escolha outra.",
    shipping_error:       "Não foi possível calcular o frete agora. Tente novamente em instantes.",
    payment_error:        "Não foi possível iniciar o pagamento agora. Tente novamente em instantes."
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

    unless result.success?
      flash[:alert] = ERROR_MESSAGES.fetch(result.error)
      return redirect_to checkout_path
    end

    payment_url = Payments::Checkout.start(
      result.order, redirect_url: checkout_return_url, webhook_url: payments_webhook_url
    )
    clear_cart!
    # Redirects to the InfinitePay hosted-checkout URL from Payments::Checkout (a trusted PSP), not user input.
    # nosemgrep: ruby.rails.security.audit.xss.avoid-redirect.avoid-redirect
    redirect_to payment_url, allow_other_host: true
  rescue InfinitePay::Api::Error
    flash[:alert] = ERROR_MESSAGES[:payment_error]
    redirect_to checkout_path
  end

  def confirmation
    @order = current_user.orders.find_by!(number: params[:order_nsu])
    record_transaction if params[:transaction_nsu].present?
    @state = payment_state
  end

  def pay
    order = current_user.orders.find_by!(number: params[:order_nsu])
    # Internal status-page path; order.number is a persisted value, not user input.
    # nosemgrep: ruby.rails.security.audit.xss.avoid-redirect.avoid-redirect
    return redirect_to checkout_return_path(order_nsu: order.number) unless order.awaiting_payment?

    # Redirects to the InfinitePay hosted-checkout URL from Payments::Checkout (a trusted PSP), not user input.
    # nosemgrep: ruby.rails.security.audit.xss.avoid-redirect.avoid-redirect
    redirect_to Payments::Checkout.start(order, redirect_url: checkout_return_url, webhook_url: payments_webhook_url),
                allow_other_host: true
  rescue InfinitePay::Api::Error
    flash[:alert] = ERROR_MESSAGES[:payment_error]
    redirect_to checkout_return_path(order_nsu: params[:order_nsu])
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

  def record_transaction
    @order.update!(
      external_id:    params[:transaction_nsu],
      receipt_url:    params[:receipt_url],
      payment_method: params[:capture_method]
    )
  end

  def payment_state
    return "failed" if @order.cancelled? || @order.payment_expired?

    @order.awaiting_payment? ? "pending" : "success"
  end

  def address_params
    params.expect(address: %i[zip street number complement neighborhood city state receiver_name receiver_cpf])
  end
end
