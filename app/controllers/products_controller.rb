class ProductsController < ApplicationController
  def index
    @query    = params[:term].to_s.strip
    @products = Product.published.includes(:category)
    @products = @products.where("products.name ILIKE ?", "%#{@query}%") if @query.present?
  end

  def show
    @product = Product.friendly.includes(:category).find(params[:slug])
  rescue ActiveRecord::RecordNotFound
    render "not_found", status: :not_found
  end
end
