module Admin
  class ProductionReportsController < BaseController
    def new
      @presenter = build_presenter
    end

    def create
      @presenter = build_presenter
      orders = @presenter.orders
      return redirect_to(admin_production_report_path(period_params), alert: t("admin.production_report.none")) if orders.empty?

      Order.transaction do
        orders.each { |order| order.transition_to!("in_production", actor: current_user) }
      end
    end

    private

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
