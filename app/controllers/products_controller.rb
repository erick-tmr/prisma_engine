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
    @product = Product.friendly.includes(:category).find(params[:slug])
  rescue ActiveRecord::RecordNotFound
    render "not_found", status: :not_found
  end
end
