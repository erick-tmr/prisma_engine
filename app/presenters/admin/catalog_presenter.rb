module Admin
  # View-model for the backoffice catalog list. Loads the products the table
  # renders and the per-row facts the design shows (category, option-group
  # count, price, status), preloading the option-group counts and Game-of-the-
  # Month membership so the table stays a single pass with no N+1.
  class CatalogPresenter
    def products
      @products ||= Product.includes(:category, product_photos: { image_attachment: :blob }).order(:name)
    end

    def count
      products.size
    end

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
