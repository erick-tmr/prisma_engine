class PagesController < ApplicationController
  def home
    @classic = Product.for_category("game-boy-classic").published.limit(8)
    @color   = Product.for_category("game-boy-color").published.limit(8)
  end

  def show
    case params[:slug]
    when "perguntas-frequentes"   then render "perguntas_frequentes"
    when "recomendacao-de-jogos"  then render "recomendacao_de_jogos"
    when "reviews"                then render "reviews"
    when "direitos"               then render "direitos"
    # :nocov:
    # The route constraint rejects unknown slugs before the controller is
    # reached; this branch is defensive guard for future widening of the
    # constraint, hence excluded from coverage.
    else raise ActionController::RoutingError, "Unknown page"
      # :nocov:
    end
  end
end
