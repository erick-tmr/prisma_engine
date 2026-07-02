class CategoriesController < ApplicationController
  def show
    @category = Category.find_by!(slug: params[:slug])
    @label    = @category.name
    @products = GameOfTheMonth.feature_first(@category.products.published.includes(:category))
  end
end
