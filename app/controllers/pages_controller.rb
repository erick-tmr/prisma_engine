class PagesController < ApplicationController
  def home
    @banners = HeroBanner.active.in_display_order.with_attached_image
    @pedidos = Product.for_category("pedidos-de-jogos").published.limit(8)
    @extras  = Product.for_category("miscelanea").published.limit(8)
    @classic = Product.for_category("game-boy-classic").published.limit(8)
    @color   = Product.for_category("game-boy-color").published.limit(8)
    @current_gotm = GameOfTheMonth.current
                                  .includes(
                                    products: [ :category, { product_photos: { image_attachment: :blob } } ],
                                    brindes:  { image_attachment: :blob }
                                  )
                                  .first
  end

  def perguntas_frequentes; end
  def direitos; end
end
