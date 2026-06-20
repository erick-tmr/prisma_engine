module Admin
  class LabelsController < BaseController
    def create
      order = Order.in_production.find_by(number: params[:number])
      return head :not_found unless order

      Shipping::EmitLabel.resume(order)
      head :accepted
    end

    def create_batch
      ids = Order.in_production.where(number: Array(params[:order_numbers])).pluck(:id)
      Shipping::EmitLabelsJob.perform_later(ids) if ids.any?
      render json: { enqueued: ids.size }, status: :accepted
    end
  end
end
