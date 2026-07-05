module Admin
  class ProductsController < Admin::BaseController
    def index
      @presenter = Admin::CatalogPresenter.new
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
      @product = Product.friendly.find(params[:id])
      @presenter = Admin::ProductFormPresenter.new(@product)
    end

    def update
      @product = Product.friendly.find(params[:id])
      persist(notice_key: "updated", template: :edit)
    end

    private

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
        :weight_grams, :currency, :published, :graph,
        photo_files: {}, brinde_files: {}
      )
    end
  end
end
