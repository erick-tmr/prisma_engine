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

  # When checkout replaces the /identificacao bounce, it will accept a
  # customer-chosen shipping service. That choice is untrusted input — the
  # cart's ineligibility rendering is UX only, and a hand-edited DOM can
  # submit any service code. The server MUST re-call
  # `Shipping::Quote.call(cep_destino:, weight_grams:)` at order creation
  # and reject unless the chosen `key` shows up with `eligible: true` in the
  # fresh quote. Correios itself will refuse the pré-postagem for an
  # ineligible service+weight combo (`Shipping::CreatePrePostagem` raises),
  # but that's the third line of defence — we should fail first, in our own
  # code, with a friendly message.
  def finalize
    if user_signed_in?
      redirect_to identificacao_path
    else
      session["user_return_to"] = identificacao_path
      redirect_to new_user_session_path,
                  notice: "Faça login ou cadastre-se para concluir sua compra."
    end
  end

  private

  def cart_cookie_value(cart)
    { value: cart.to_cookie, expires: 30.days.from_now }
  end
end
