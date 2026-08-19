module Admin
  class LabelsController < BaseController
    RESTARTABLE_STATUSES = ([ "in_production" ] + Shipping::RETURN_WALK).freeze

    def create
      order = Order.where(status: RESTARTABLE_STATUSES).find_by(number: params[:number])
      return head :not_found unless order

      Shipping::EmitLabel.restart(order.tracked_shipment)
      head :accepted
    end

    def reissue
      shipment = Order.find_by(number: params[:number])&.tracked_shipment
      return head :not_found unless Shipping::ReissueLabel.call(shipment)

      head :accepted
    end

    def create_batch
      scope = Order.where(number: Array(params[:order_numbers]))
      emitting = scope.in_production.ids
      reissuing = scope.label_reissuable.ids
      Shipping::EmitLabelsJob.perform_later(emitting) if emitting.any?
      Shipping::ReissueLabelsJob.perform_later(reissuing) if reissuing.any?
      render json: { enqueued: emitting.size + reissuing.size }, status: :accepted
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
