module Admin
  class ProductsController < Admin::BaseController
    before_action :set_product, only: %i[edit update]

    def index
      @search = Admin::CatalogSearch.new(params)
      @base_params = @search.to_params
      @page = Admin::Page.new(@search.relation, page_param)
      @presenter = Admin::CatalogPresenter.new(@page.rows)
      render_list "results"
    end

    def new
      @product = Admin::ProductFormPresenter.build_new
      @presenter = Admin::ProductFormPresenter.new(@product)
    end

    def create
      @product = Product.new
      persist(notice_key: "created", template: :new)
    end

    def edit
      @presenter = Admin::ProductFormPresenter.new(@product)
    end

    def update
      persist(notice_key: "updated", template: :edit)
    end

    private

    def set_product
      @product = Product.friendly.find(params[:id]) # nosemgrep: ruby.rails.security.brakeman.check-unscoped-find.check-unscoped-find
    end

    def persist(notice_key:, template:)
      if Catalog::SaveProduct.call(product: @product, params: product_params).success?
        redirect_to admin_products_path, notice: t("admin.catalog.#{notice_key}", name: @product.name)
      else
        @presenter = Admin::ProductFormPresenter.new(@product, submitted_graph: product_params[:graph])
        flash.now[:alert] = t("admin.catalog.invalid")
        render template, status: :unprocessable_entity
      end
    end

    def product_params
      @product_params ||= params.require(:product).permit(
        :name, :slug, :category_id, :price, :description,
        :weight_grams, :currency, :published, :custom_order, :graph,
        photo_files: {}, brinde_files: {}, custom_order_form: CustomOrderForm::LIMITS.keys
      )
    end
  end
end
