module Admin
  class OrderMergesController < BaseController
    def preview
      result = merger.preview
      render partial: "admin/order_merges/confirm", locals: { result: result }
    end

    def create
      result = merger.call(actor: current_user)
      if result.success?
        flash[:notice] = done_notice(result.preview)
      else
        flash[:alert] = t("admin.orders.merge.errors.#{result.error}")
      end
      # nosemgrep: ruby.rails.security.audit.xss.avoid-redirect.avoid-redirect -- internal path helper from a DB record, not a user-supplied URL
      redirect_to admin_order_path(master)
    end

    private

    def master
      @master ||= Order.includes(:user, :order_items, shipment: :shipping_label).find_by!(number: params[:number])
    end

    def merger
      MergeOrders.new(master: master, numbers: params[:numbers])
    end

    def done_notice(preview)
      t("admin.orders.merge.done", count: preview.absorbed.size, number: master.number,
                                   total: HasMoney.format(master.reload.total_cents))
    end
  end
end
