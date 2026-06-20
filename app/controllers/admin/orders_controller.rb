module Admin
  class OrdersController < BaseController
    def show
      @order = find_order
      @presenter = OrderPresenter.new(@order)
    end

    def transition
      order = find_order
      action = OrderActions.find(params[:event])
      return reject(order) if action.nil? || !action.available_for?(order.status)

      apply(order, action)
      redirect_to admin_order_path(order), notice: notice_for(order, action)
    end

    def label
      label = find_order.shipping_label
      return head :not_found unless label&.ready?

      send_data Base64.decode64(label.pdf_base64),
                type: "application/pdf", disposition: "inline", filename: label.filename
    end

    private

    def find_order
      Order.includes(:user, :order_items, { status_changes: :actor }, { shipment: :tracking_events })
           .find_by!(number: params[:number])
    end

    def apply(order, action)
      if action.saga
        Shipping::EmitLabel.resume(order)
      else
        order.transition_to!(action.to, actor: current_user)
      end
    end

    def notice_for(order, action)
      return t("admin.orders.detail.label_requested") if action.saga

      t("admin.orders.detail.transition_done",
        status: I18n.t("account.orders.states.#{order.status}.label"))
    end

    def reject(order)
      redirect_to admin_order_path(order), alert: t("admin.orders.detail.transition_invalid")
    end
  end
end
