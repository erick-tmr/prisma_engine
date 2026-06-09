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
