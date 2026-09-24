module Admin
  class ProductionReportsController < BaseController
    def new
      @presenter = report
    end

    def create
      orders = eligible_orders
      return redirect_to(admin_production_report_path(period_params), alert: t("admin.production_report.none")) if orders.empty?

      Production::SendOrders.call(orders: orders, operator: current_user)
      @presenter = report
      render :show
    end

    private

    def report
      ProductionReportPresenter.new(orders: eligible_orders, from: period_param(:de), to: period_param(:ate))
    end

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
