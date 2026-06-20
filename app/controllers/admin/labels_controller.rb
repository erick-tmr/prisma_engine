module Admin
  class LabelsController < BaseController
    def create
      ids = Order.where(number: Array(params[:order_numbers]), status: "in_production").pluck(:id)
      Shipping::EmitLabelsJob.perform_later(ids) if ids.any?
      render json: { enqueued: ids.size }, status: :accepted
    end
  end
end
