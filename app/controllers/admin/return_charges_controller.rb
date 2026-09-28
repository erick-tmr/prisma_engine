module Admin
  class ReturnChargesController < BaseController
    def create
      act_on(Shipping::RenewReturnCharge, "renewed")
    end

    def resend
      act_on(Shipping::ResendReturnCharge, "resent")
    end

    def waive
      act_on(Shipping::AssumeReturnFreight, "waived")
    end

    private

    def act_on(action, notice_key)
      order = Order.find_by!(number: params[:number])
      result = action.call(order: order)
      if result.success?
        flash[:notice] = t("admin.orders.return_charges.#{notice_key}")
      else
        flash[:alert] = t("admin.orders.return_charges.errors.#{result.error}")
      end
      # nosemgrep: ruby.rails.security.audit.xss.avoid-redirect.avoid-redirect -- internal path helper from a DB record, not a user-supplied URL
      redirect_to admin_order_path(order)
    end
  end
end
