class CategoriesController < ApplicationController
  def show
    @slug = params[:slug]
    @category_id = params[:category_id]
  end
end
