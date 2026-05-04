class PagesController < ApplicationController
  def home
    @featured = Product.featured(8)
    @classic  = Product.for_category("game-boy-classic").first(4)
    @color    = Product.for_category("game-boy-color").first(4)
  end

  def show
    render params[:slug].tr("-", "_")
  end
end
