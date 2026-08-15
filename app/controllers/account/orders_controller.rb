module Account
  class OrdersController < BaseController
    def index
      @orders = current_user.orders.where.not(status: :merged).recent_first
    end

    def show
      @order = find_order
    end

    def return_label
      label = current_user.orders.find_by!(number: params[:id]).return_shipping_label
      return head :not_found unless label&.ready?

      send_data label.pdf_bytes,
                type: "application/pdf", disposition: "inline", filename: label.filename
    end

    private

    def find_order
      current_user.orders
                  .includes(order_items: OrderItem::PHOTO_INCLUDES, shipment: :tracking_events,
                            return_shipment: [ :tracking_events, :shipping_label ])
                  .find_by!(number: params[:id])
    end
  end
end
