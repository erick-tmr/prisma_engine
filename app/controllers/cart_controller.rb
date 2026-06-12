class CartController < ApplicationController
  def show
    @cart = current_cart
    if @cart.cleanup!
      cookies.signed[:cart] = cart_cookie_value(@cart)
      flash.now[:alert] = "Um item do seu carrinho não está mais disponível e foi removido."
    end
    @lines = @cart.lines
    gotm = GameOfTheMonth.current.first
    @gotm_product_ids = gotm ? gotm.products.pluck(:id).to_set : Set.new
  end

  # Checkout — the redirect target below — accepts a customer-chosen shipping
  # service. That choice is untrusted input: the cart's ineligibility rendering
  # is UX only, and a hand-edited DOM can submit any service code. The server
  # MUST re-call `Shipping::Quote.call(cep_destino:, weight_grams:)` at order
  # creation and reject unless the chosen `key` shows up with `eligible: true`
  # in the fresh quote. Correios itself will refuse the pré-postagem for an
  # ineligible service+weight combo (`Shipping::CreatePrePostagem` raises), but
  # that's the third line of defence — we should fail first, in our own code,
  # with a friendly message.
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

  # Bridge the cart's client-side frete pick to the checkout screen, which
  # reads it back to pre-select the same service. Whitelisted against our
  # known services so a hand-edited form can't stash arbitrary input; the
  # binding re-validation against a fresh quote still happens at order time.
  def remember_shipping_choice
    service = params[:shipping_service].to_s
    if Shipping::SERVICES.keys.any? { |key| key.to_s == service }
      session["checkout_shipping_service"] = service
    else
      session.delete("checkout_shipping_service")
    end
  end

  def cart_cookie_value(cart)
    { value: cart.to_cookie, expires: 30.days.from_now }
  end
end
