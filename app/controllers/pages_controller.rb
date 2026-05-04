class PagesController < ApplicationController
  def home
  end

  def show
    render params[:slug].tr("-", "_")
  end
end
