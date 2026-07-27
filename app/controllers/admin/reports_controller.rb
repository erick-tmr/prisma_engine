module Admin
  class ReportsController < BaseController
    def index
      @page = Admin::Page.new(ProductionBatch.includes(:operator).recent_first, page_param)
      @batches = @page.rows
      render_list "results"
    end
  end
end
