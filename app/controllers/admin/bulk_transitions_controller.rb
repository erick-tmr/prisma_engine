module Admin
  class BulkTransitionsController < BaseController
    def create
      result = Admin::BulkTransition.call(
        order_numbers: params[:order_numbers],
        event: params[:event],
        actor: current_user,
        service: params[:service]
      )
      render json: result
    end
  end
end
