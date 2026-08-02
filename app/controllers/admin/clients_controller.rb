module Admin
  class ClientsController < BaseController
    ORDERS_PER_PAGE = 8

    def index
      @search = Admin::ClientSearch.new(params)
      @base_params = @search.to_params
      @page = Admin::Page.new(@search.relation, page_param)
      @clients = @page.rows
      render_list "results"
    end

    def show
      # nosemgrep: ruby.rails.security.brakeman.check-unscoped-find.check-unscoped-find -- backoffice: BaseController#require_admin gates the whole namespace, and an operator is meant to open any client
      @client = User.clients.find(params[:id])
      @presenter = Admin::ClientPresenter.new(@client)
      @page = Admin::Page.new(@client.orders.recent_first.preload(:order_items),
                              page_param, per: ORDERS_PER_PAGE)
      @orders = @page.rows
      render_list "orders"
    end
  end
end
