class PagesController < ApplicationController
  def home
    @banners = HeroBanner.active.in_display_order.with_attached_image
    @pedidos = GameOfTheMonth.feature_first(Product.for_category("pedidos-de-jogos").published).first(8)
    @extras  = GameOfTheMonth.feature_first(Product.for_category("miscelanea").published).first(8)
    @classic = GameOfTheMonth.feature_first(Product.for_category("game-boy-classic").published).first(8)
    @color   = GameOfTheMonth.feature_first(Product.for_category("game-boy-color").published).first(8)
    @current_gotm = GameOfTheMonth.current
                                  .includes(
                                    game_of_the_month_products: {
                                      product: [ :category, { product_photos: { image_attachment: :blob } } ],
                                      brindes: { image_attachment: :blob }
                                    }
                                  )
                                  .first
  end

  def perguntas_frequentes; end
  def direitos; end
end
