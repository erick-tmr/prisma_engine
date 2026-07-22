module Admin
  class BaseController < ApplicationController
    before_action :require_admin
    helper_method :sidebar_counts
    layout "admin"

    private

    def require_admin
      redirect_to admin_login_path unless current_user&.admin?
    end

    def sidebar_counts
      @sidebar_counts ||= {
        "orders" => Order.count,
        "clients" => User.where(admin: false).count,
        "reports" => ProductionBatch.count,
        "catalog" => Product.count
      }
    end
  end
end
