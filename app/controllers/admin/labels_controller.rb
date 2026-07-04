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

    def print_sheet
      orders = Order.where(number: Array(params[:order_numbers])).includes(shipment: :shipping_label)
      sheet = Shipping::LabelSheet.call(orders: orders)
      return head :unprocessable_entity if sheet.composed.zero?

      response.set_header("X-Skipped-Count", sheet.skipped.to_s)
      send_data sheet.pdf, type: "application/pdf", disposition: "inline", filename: "etiquetas.pdf"
    end
  end
end
