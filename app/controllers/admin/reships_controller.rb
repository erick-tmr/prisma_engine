module Admin
  class ReshipsController < BaseController
    def create
      order = Order.find_by!(number: params[:number])
      result = Shipping::Reship.call(order: order, service: params[:service])
      if result.success?
        flash[:notice] = t("admin.orders.reship.started")
      else
        flash[:alert] = t("admin.orders.reship.errors.#{result.error}")
      end
      # nosemgrep: ruby.rails.security.audit.xss.avoid-redirect.avoid-redirect -- internal path helper from a DB record, not a user-supplied URL
      redirect_to admin_order_path(order)
    end
  end
end
