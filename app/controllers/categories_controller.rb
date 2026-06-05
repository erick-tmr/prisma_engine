class CategoriesController < ApplicationController
  def show
    @category = Category.find_by!(slug: params[:slug])
    @label    = @category.name
    @products = @category.products.published.includes(:category)
  rescue ActiveRecord::RecordNotFound
    render "products/not_found", status: :not_found
  end
end
