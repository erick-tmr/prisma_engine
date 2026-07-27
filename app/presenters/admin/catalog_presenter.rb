module Admin
  class CatalogPresenter
    def initialize(products)
      @products = products
    end

    attr_reader :products

    def categories
      Category.order(:name).pluck(:name, :slug)
    end

    def option_group_count(product)
      group_counts.fetch(product.id, 0)
    end

    def status(product)
      return :gotm if gotm_product_ids.include?(product.id)

      product.published? ? :published : :draft
    end

    private

    def group_counts
      @group_counts ||= ProductOption.where(product_id: products.map(&:id))
                                     .where.not(group_name: nil)
                                     .distinct
                                     .group(:product_id)
                                     .count(:group_name)
    end

    def gotm_product_ids
      @gotm_product_ids ||= GameOfTheMonthProduct.where(product_id: products.map(&:id))
                                                 .distinct
                                                 .pluck(:product_id)
                                                 .to_set
    end
  end
end
