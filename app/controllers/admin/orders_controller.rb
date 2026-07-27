module Admin
  class OrdersController < BaseController
    def index
      @search = Admin::OrderSearch.new(params)
      @base_params = @search.to_params
      @page = Admin::Page.new(@search.relation, page_param)
      @orders = @page.rows
      @total_cents = @search.total_cents
      render_list "results"
    end

    def show
      @order = find_order
      @presenter = OrderPresenter.new(@order)
    end

    def transition
      order = find_order
      action = OrderActions.lookup(params[:event])
      return reject(order) if action.nil? || !action.available_for?(order.status)

      order.transition_to!(action.to, actor: current_user)
      # nosemgrep: ruby.rails.security.audit.xss.avoid-redirect.avoid-redirect -- internal path helper from a DB record, not a user-supplied URL
      redirect_to admin_order_path(order), notice: notice_for(order)
    end

    def label
      label = find_order.shipping_label
      return head :not_found unless label&.ready?

      send_data label.pdf_bytes,
                type: "application/pdf", disposition: "inline", filename: label.filename
    end

    private

    def find_order
      Order.includes(:user, { order_items: OrderItem::PHOTO_INCLUDES },
                     { status_changes: :actor }, { shipment: :tracking_events })
           .find_by!(number: params[:number])
    end

    def notice_for(order)
      t("admin.orders.detail.transition_done",
        status: I18n.t("account.orders.states.#{order.status}.label"))
    end

    def reject(order)
      # nosemgrep: ruby.rails.security.audit.xss.avoid-redirect.avoid-redirect -- internal path helper from a DB record, not a user-supplied URL
      redirect_to admin_order_path(order), alert: t("admin.orders.detail.transition_invalid")
    end
  end
end
