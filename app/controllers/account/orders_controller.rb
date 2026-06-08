module Account
  class OrdersController < BaseController
    def index
      @orders = MockOrders.all_for(current_user)
    end

    def show
      @order = MockOrders.lookup(current_user, params[:id])
      raise ActiveRecord::RecordNotFound unless @order
    end
  end
end
