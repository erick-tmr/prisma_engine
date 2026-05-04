class ProductsController < ApplicationController
  def index
    @query    = params[:term].to_s.strip
    @products = if @query.present?
                  Product.all.select { |p| p.title.downcase.include?(@query.downcase) }
                else
                  Product.all
                end
  end

  def show
    @product = Product.find_by_slug_and_id(params[:slug], params[:id])
    return render "not_found", status: :not_found unless @product
  end
end
