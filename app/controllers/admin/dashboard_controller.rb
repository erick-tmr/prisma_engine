module Admin
  class DashboardController < BaseController
    def index
      @dashboard = DashboardPresenter.new
    end
  end
end
