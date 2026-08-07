module Admin
  class LabelFeedbackController < BaseController
    BATCH_LIMIT = 200

    def index
      page = Admin::Page.new(Admin::OrderSearch.new(params).relation, page_param)
      render partial: "admin/orders/label_feedback",
             locals: { feedbacks: page.rows.map { |order| LabelFeedback.new(order) }, batch: batch },
             layout: false
    end

    def show
      order = Order.includes({ status_changes: :actor }, { shipment: :shipping_label })
                   .find_by!(number: params[:number])
      render partial: "admin/orders/label_status",
             locals: { presenter: OrderPresenter.new(order) }, layout: false
    end

    private

    def batch
      LabelBatch.for(Order.where(number: batch_numbers).preload(shipment: :shipping_label))
    end

    def batch_numbers
      Array(params[:lote]).first(BATCH_LIMIT)
    end
  end
end
