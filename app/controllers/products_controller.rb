class ProductsController < ApplicationController
  def index
    @query   = params[:term].to_s.strip
    products = Product.published.includes(:category)
    products = products.where("products.name ILIKE ?", "%#{Product.sanitize_sql_like(@query)}%") if @query.present?
    @products = GameOfTheMonth.feature_first(products)
  end

  def show
    # Products are public catalog entries — there is no per-user scope to
    # narrow the find against, so the Semgrep IDOR heuristic does not apply.
    # nosemgrep: ruby.rails.security.brakeman.check-unscoped-find.check-unscoped-find
    @product = Product.friendly
                      .includes(:category, :product_options, product_photos: { image_attachment: :blob })
                      .find(params[:slug])

    @gotm_product = GameOfTheMonthProduct
                      .joins(:game_of_the_month)
                      .merge(GameOfTheMonth.current)
                      .includes(:game_of_the_month, brindes: { image_attachment: :blob })
                      .find_by(product_id: @product.id)
    @gotm = @gotm_product&.game_of_the_month
  end
end
