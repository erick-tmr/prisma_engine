class PagesController < ApplicationController
  def home
    @banners = HeroBanner.active.in_display_order.with_attached_image
    @current_gotm = GameOfTheMonth.current
                                  .includes(
                                    published_picks: {
                                      product: [ :category, { product_photos: { image_attachment: :blob } } ],
                                      brindes: { image_attachment: :blob }
                                    }
                                  )
                                  .first
    featured_ids = @current_gotm&.published_picks&.map(&:product_id) || []

    @pedidos = GameOfTheMonth.feature_first(published_cards_for("pedidos-de-jogos"), featured_ids).first(8)
    @extras  = GameOfTheMonth.feature_first(published_cards_for("miscelanea"), featured_ids).first(8)
    @classic = GameOfTheMonth.feature_first(published_cards_for("game-boy-classic"), featured_ids).first(8)
    @color   = GameOfTheMonth.feature_first(published_cards_for("game-boy-color"), featured_ids).first(8)
  end

  def perguntas_frequentes; end
  def direitos; end

  private

  def published_cards_for(slug)
    Product.for_category(slug).published
           .includes(:category, product_photos: { image_attachment: :blob })
  end
end
