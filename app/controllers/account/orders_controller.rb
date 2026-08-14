module Account
  class OrdersController < BaseController
    def index
      @orders = current_user.orders.where.not(status: :merged).recent_first
    end

    def show
      @order = find_order
    end

    private

    def find_order
      current_user.orders
                  .includes(order_items: OrderItem::PHOTO_INCLUDES, shipment: :tracking_events)
                  .find_by!(number: params[:id])
    end
  end
end
