module Admin
  class ReturnsController < BaseController
    def create
      order = find_order
      result = Shipping::AuthorizeReturn.call(order: order, actor: current_user)
      respond_with(order, result, "authorized")
    end

    def destroy
      order = find_order
      result = Shipping::CancelReturn.call(order: order, actor: current_user)
      respond_with(order, result, "cancelled")
    end

    private

    def find_order
      Order.find_by!(number: params[:number])
    end

    def respond_with(order, result, notice_key)
      flash_for(result, notice_key)
      # nosemgrep: ruby.rails.security.audit.xss.avoid-redirect.avoid-redirect -- internal path helper from a DB record, not a user-supplied URL
      redirect_to admin_order_path(order)
    end

    def flash_for(result, notice_key)
      if result.success?
        flash[:notice] = t("admin.orders.returns.#{notice_key}")
      else
        flash[:alert] = t("admin.orders.returns.errors.#{result.error}")
      end
    end
  end
end
