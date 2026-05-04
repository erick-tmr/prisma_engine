class PagesController < ApplicationController
  def home
    @featured = Product.featured(8)
    @classic  = Product.for_category("game-boy-classic").first(4)
    @color    = Product.for_category("game-boy-color").first(4)
  end

  def show
    case params[:slug]
    when "perguntas-frequentes"   then render "perguntas_frequentes"
    when "recomendacao-de-jogos"  then render "recomendacao_de_jogos"
    when "reviews"                then render "reviews"
    when "direitos"               then render "direitos"
    else
      raise ActionController::RoutingError, "Unknown page"
    end
  end
end
