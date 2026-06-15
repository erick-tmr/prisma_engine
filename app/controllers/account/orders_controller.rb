module Account
  class OrdersController < BaseController
    def index
      @orders = current_user.orders.recent_first
    end

    def show
      @order = find_order
    end

    def cancel
      order = find_order
      if order.cancellable?
        order.cancel_by_customer!
        redirect_to account_order_path(order), notice: t("account.orders.cancel.#{order.status}")
      else
        redirect_to account_order_path(order), alert: t("account.orders.cancel.unavailable")
      end
    end

    private

    def find_order
      current_user.orders
                  .includes(:order_items, shipment: :tracking_events)
                  .find_by!(number: params[:id])
    end
  end
end
