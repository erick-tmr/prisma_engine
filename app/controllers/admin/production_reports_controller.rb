module Admin
  class ProductionReportsController < BaseController
    def new
      @presenter = ProductionReportPresenter.new(orders: eligible_orders, from: period_param(:de), to: period_param(:ate))
    end

    def create
      orders = eligible_orders
      return redirect_to(admin_production_report_path(period_params), alert: t("admin.production_report.none")) if orders.empty?

      batch = Production::SendBatch.call(orders: orders, operator: current_user, from: period_param(:de), to: period_param(:ate))
      redirect_to admin_production_report_batch_path(batch)
    end

    def show
      # nosemgrep: ruby.rails.security.brakeman.check-unscoped-find.check-unscoped-find -- admin-only action (require_admin); production batches are a global operational resource, not user-scoped
      @batch = ProductionBatch.find(params[:id])
      @presenter = ProductionReportPresenter.for_batch(@batch)
    end

    private

    def eligible_orders
      Production::EligibleOrders.within(from: period_param(:de), to: period_param(:ate))
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
