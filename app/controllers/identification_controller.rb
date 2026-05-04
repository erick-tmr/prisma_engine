class IdentificationController < ApplicationController
  def show
  end

  def create
    flash.now[:alert] = "Login ainda não está conectado ao backend."
    render :show
  end
end
