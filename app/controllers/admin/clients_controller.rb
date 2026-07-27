module Admin
  class ClientsController < BaseController
    def index
      @search = Admin::ClientSearch.new(params)
      @base_params = @search.to_params
      @page = Admin::Page.new(@search.relation, page_param)
      @clients = @page.rows
      render_list "results"
    end
  end
end
