module Admin
  class BaseController < ApplicationController
    before_action :require_admin
    helper_method :sidebar_counts
    layout "admin"

    private

    def require_admin
      redirect_to admin_login_path unless current_user&.admin?
    end

    # The table JS refetches only the results region; the same action serves the
    # whole page on a normal navigation.
    def fragment_request?
      request.headers["X-Requested-With"] == "fetch"
    end

    def render_list(partial)
      return unless fragment_request?

      render partial: partial, layout: false
    end

    def page_param
      params[:page]
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
