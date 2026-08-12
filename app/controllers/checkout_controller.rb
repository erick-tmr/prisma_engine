class CheckoutController < ApplicationController
  include CheckoutErrors

  before_action :authenticate_user!

  layout "checkout"

  def show
    render_checkout
  end

  def create
    result = place_order
    return render_create_failure(ERROR_MESSAGES.fetch(result.error)) unless result.success?

    redirect_to_payment(result)
  end

  def create_address
    @address = current_user.addresses.build(address_params)
    if @address.save
      session["checkout_address_id"] = @address.id
      return redirect_to checkout_path
    end

    log_address_rejection
    render_checkout(status: :unprocessable_entity)
  end

  private

  def render_checkout(status: :ok)
    @cart = current_cart
    persist_cart_if_cleaned
    return redirect_to cart_path, notice: ERROR_MESSAGES[:empty_cart] if @cart.empty?

    load_delivery_choices
    render :show, status: status
  end

  def load_delivery_choices
    @address ||= current_user.addresses.build
    @addresses = current_user.addresses.default_first
    @selected_address = address_chosen_in_session || @addresses.first
    @selected_shipping_service = session["checkout_shipping_service"]
    @mergeable_orders = current_user.orders.mergeable.includes(:shipment, order_items: OrderItem::PHOTO_INCLUDES)
  end

  def log_address_rejection
    Rails.logger.info(
      "[Checkout] address rejected user=#{current_user.id} fields=#{@address.errors.attribute_names.join(',')}"
    )
  end

  def address_chosen_in_session
    chosen_id = session.delete("checkout_address_id").to_i
    @addresses.find { |addr| addr.id == chosen_id }
  end

  def place_order
    if merge_requested?
      Checkout::PlaceMergeOrder.call(
        user: current_user, cart: current_cart, payment_link: payment_link,
        observation: params[:observation], receiver_obs: params[:receiver_obs]
      )
    else
      Checkout::PlaceOrder.call(
        user: current_user, cart: current_cart, payment_link: payment_link,
        address_id: params[:address_id], shipping_service: params[:shipping_service],
        observation: params[:observation], receiver_obs: params[:receiver_obs]
      )
    end
  end

  def payment_link
    lambda do |order|
      Payments::Checkout.start(
        order, redirect_url: checkout_return_url, webhook_url: payments_webhook_url(order.webhook_token)
      )
    end
  end

  def merge_requested?
    ActiveModel::Type::Boolean.new.cast(params[:merge_everything])
  end

  def redirect_to_payment(result)
    payment_url = result.payment_url
    clear_cart!
    respond_to do |format|
      format.json { render json: { payment_url:, return_url: checkout_return_url(order_nsu: result.order.number) } }
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
