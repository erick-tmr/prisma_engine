module Admin
  class ClientsController < BaseController
    ORDERS_PER_PAGE = 8
    CONTACT_FIELDS = %w[email phone].freeze

    def index
      @search = Admin::ClientSearch.new(params)
      @base_params = @search.to_params
      @page = Admin::Page.new(@search.relation, page_param)
      @clients = @page.rows
      render_list "results"
    end

    def show
      load_detail(find_client)
      render_list "orders"
    end

    def update
      @contact = find_client
      if @contact.update_contact(params.expect(client: CONTACT_FIELDS.map(&:to_sym)))
        redirect_to admin_client_path(@contact), notice: contact_notice
      else
        load_detail(find_client)
        render :show, status: :unprocessable_entity
      end
    end

    private

    def find_client
      # nosemgrep: ruby.rails.security.brakeman.check-unscoped-find.check-unscoped-find -- backoffice: BaseController#require_admin gates the whole namespace, and an operator is meant to open any client
      User.clients.find(params[:id])
    end

    def load_detail(client)
      @contact ||= client
      @presenter = Admin::ClientPresenter.new(client)
      @page = Admin::Page.new(client.orders.recent_first.preload(:order_items), page_param, per: ORDERS_PER_PAGE)
      @orders = @page.rows
    end

    def contact_notice
      changed = CONTACT_FIELDS & @contact.saved_changes.keys
      scope = "admin.clients.detail.contact"
      return t("#{scope}.unchanged", name: @contact.first_name) if changed.empty?

      fields = changed.map { |field| t("#{scope}.fields.#{field}") }.to_sentence
      t("#{scope}.updated", fields: fields, name: @contact.first_name)
    end
  end
end
