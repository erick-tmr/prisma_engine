class CheckoutController < ApplicationController
  include CheckoutErrors

  before_action :authenticate_user!

  layout "checkout"

  def show
    @cart = current_cart
    persist_cart_if_cleaned
    return redirect_to cart_path, notice: ERROR_MESSAGES[:empty_cart] if @cart.empty?

    @addresses = current_user.addresses.default_first
    chosen_id  = session.delete("checkout_address_id").to_i
    @selected_address = @addresses.find { |addr| addr.id == chosen_id } || @addresses.first
    @selected_shipping_service = session["checkout_shipping_service"]
    @mergeable_orders = current_user.orders.mergeable.includes(:shipment, :order_items)
  end

  def create
    result = place_order
    return render_create_failure(ERROR_MESSAGES.fetch(result.error)) unless result.success?

    start_payment(result.order)
  rescue InfinitePay::Api::Error
    render_create_failure(ERROR_MESSAGES[:payment_error])
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

  def place_order
    if merge_requested?
      Checkout::PlaceMergeOrder.call(user: current_user, cart: current_cart, observation: params[:observation])
    else
      Checkout::PlaceOrder.call(
        user: current_user, cart: current_cart,
        address_id: params[:address_id], shipping_service: params[:shipping_service],
        observation: params[:observation]
      )
    end
  end

  def merge_requested?
    ActiveModel::Type::Boolean.new.cast(params[:merge_everything])
  end

  def start_payment(order)
    payment_url = Payments::Checkout.start(
      order, redirect_url: checkout_return_url, webhook_url: payments_webhook_url(order.webhook_token)
    )
    clear_cart!
    respond_to do |format|
      format.json { render json: { payment_url:, return_url: checkout_return_url(order_nsu: order.number) } }
      # nosemgrep: ruby.rails.security.audit.xss.avoid-redirect.avoid-redirect
      format.html { redirect_to payment_url, allow_other_host: true }
    end
  end

  def persist_cart_if_cleaned
    cookies.signed[:cart] = { value: @cart.to_cookie, expires: 30.days.from_now } if @cart.cleanup!
  end

  def clear_cart!
    cookies.delete(:cart)
    session.delete("checkout_shipping_service")
  end

  def render_create_failure(message)
    respond_to do |format|
      format.json { render json: { error: message }, status: :unprocessable_entity }
      format.html do
        flash[:alert] = message
        redirect_to checkout_path
      end
    end
  end

  def address_params
    params.expect(address: %i[zip street number complement neighborhood city state receiver_name receiver_cpf])
  end
end
