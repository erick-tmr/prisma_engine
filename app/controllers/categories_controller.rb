class CategoriesController < ApplicationController
  def show
    @category = Category.find_by!(slug: params[:slug])
    @label    = @category.name
    @products = gotm_first(@category.products.published.includes(:category))
  end

  private

  def gotm_first(products)
    gotm_ids = GameOfTheMonth.current.first&.product_ids || []
    featured, rest = products.order(:id).partition { |product| gotm_ids.include?(product.id) }
    featured + rest
  end
end
