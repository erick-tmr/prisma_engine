module Admin
  class ProductionReportsController < BaseController
    def new
      @presenter = build_presenter
    end

    def create
      orders = build_presenter.orders
      return redirect_to(admin_production_report_path(period_params), alert: t("admin.production_report.none")) if orders.empty?

      batch = send_to_production(orders)
      redirect_to admin_production_report_batch_path(batch)
    end

    def show
      # nosemgrep: ruby.rails.security.brakeman.check-unscoped-find.check-unscoped-find -- admin-only action (require_admin); production batches are a global operational resource, not user-scoped
      @batch = ProductionBatch.find(params[:id])
      @presenter = ProductionReportPresenter.for_batch(@batch)
    end

    private

    def send_to_production(orders)
      Order.transaction do
        batch = ProductionBatch.create!(
          operator: current_user, period_from: period_param(:de), period_to: period_param(:ate), orders_count: orders.size
        )
        orders.each { |order| order.transition_to!("in_production", actor: current_user) }
        Order.where(id: orders.map(&:id)).update_all(production_batch_id: batch.id)
        batch
      end
    end

    def build_presenter
      ProductionReportPresenter.new(from: period_param(:de), to: period_param(:ate))
    end

    def period_param(key)
      raw = params[key].to_s
      return if raw.blank?

      Date.iso8601(raw)
    rescue ArgumentError
      nil
    end

    def period_params
      params.permit(:de, :ate).to_h.compact_blank
    end
  end
end
