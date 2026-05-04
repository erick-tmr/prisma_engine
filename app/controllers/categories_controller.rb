class CategoriesController < ApplicationController
  def show
    @slug     = params[:slug]
    @label    = Product::CATEGORY_LABELS[@slug] || @slug.tr("-", " ").titleize
    @products = Product.for_category(@slug)
  end
end
