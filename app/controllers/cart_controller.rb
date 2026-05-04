class CartController < ApplicationController
  def show
  end

  def create
    redirect_to "/carrinho", notice: "Carrinho ainda não está conectado ao backend."
  end
end
