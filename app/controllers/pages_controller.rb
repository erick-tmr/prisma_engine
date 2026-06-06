class PagesController < ApplicationController
  def home
    @classic = Product.for_category("game-boy-classic").published.limit(8)
    @color   = Product.for_category("game-boy-color").published.limit(8)
  end

  # One explicit action per static page — each renders its matching template
  # under app/views/pages/. Adding a new page = adding a route + an action
  # + a template; no central case statement to keep in sync.
  def perguntas_frequentes; end
  def recomendacao_de_jogos; end
  def reviews; end
  def direitos; end
end
