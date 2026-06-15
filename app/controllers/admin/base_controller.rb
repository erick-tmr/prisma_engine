module Admin
  class BaseController < ApplicationController
    before_action :require_admin
    layout "admin"

    private

    def require_admin
      redirect_to admin_login_path unless current_user&.admin?
    end
  end
end
