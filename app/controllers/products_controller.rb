class ProductsController < ApplicationController
  def index
    @query = params[:q].to_s
  end

  def show
    @slug = params[:slug]
    @product_id = params[:id]
  end
end
