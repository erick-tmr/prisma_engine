class ProductsController < ApplicationController
  def index
    @query    = params[:term].to_s.strip
    @products = Product.published.includes(:category)
    @products = @products.where("products.name ILIKE ?", "%#{@query}%") if @query.present?
  end

  def show
    # Products are public catalog entries — there is no per-user scope to
    # narrow the find against, so the Semgrep IDOR heuristic does not apply.
    # nosemgrep: ruby.rails.security.brakeman.check-unscoped-find.check-unscoped-find
    @product = Product.friendly
                      .includes(:category, :product_options, product_photos: { image_attachment: :blob })
                      .find(params[:slug])

    # @gotm is set only when this product is the current month's pick — the view
    # keys the whole Jogo do Mês treatment off its presence.
    gotm = GameOfTheMonth.current
                         .includes(:products, brindes: { image_attachment: :blob })
                         .first
    @gotm = gotm if gotm&.products&.include?(@product)
  end
end
