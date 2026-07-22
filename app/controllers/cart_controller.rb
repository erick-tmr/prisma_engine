class CartController < ApplicationController
  include RemembersShipping

  QUOTE_TTL = 30.minutes.to_i

  Quote = Data.define(:initial, :recalc_cep, :recalc_service)

  def show
    @cart = current_cart
    if @cart.cleanup!
      cookies.signed[:cart] = cart_cookie_value(@cart)
      flash.now[:alert] = "Um item do seu carrinho não está mais disponível e foi removido."
    end
    @lines = @cart.lines
    @gotm_product_ids = current_gotm_product_ids
    @quote = build_quote
  end

  def finalize
    remember_shipping_choice
    if user_signed_in?
      redirect_to checkout_path
    else
      session["user_return_to"] = checkout_path
      redirect_to new_user_session_path,
                  notice: "Faça login ou cadastre-se para concluir sua compra."
    end
  end

  private

  def cart_cookie_value(cart)
    { value: cart.to_cookie, expires: 30.days.from_now }
  end

  def current_gotm_product_ids
    gotm = GameOfTheMonth.current.first
    gotm ? gotm.products.pluck(:id).to_set : Set.new
  end

  def build_quote
    initial = restored_quote
    Quote.new(
      initial:        initial,
      recalc_cep:     initial ? nil : fresh_quote&.dig("response", "cep"),
      recalc_service: session["checkout_shipping_service"]
    )
  end

  def restored_quote
    cached = fresh_quote
    return unless cached && cached["weight"].to_i == Shipping::PackageWeight.call(@cart)

    { "response" => cached["response"], "service" => session["checkout_shipping_service"] }
  end

  def fresh_quote
    cached = session["cart_quote"]
    cached if cached && Time.current.to_i - cached["at"].to_i <= QUOTE_TTL
  end
end
