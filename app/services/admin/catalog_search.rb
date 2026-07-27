module Admin
  class CatalogSearch
    STATUSES = %w[published draft gotm].freeze

    GOTM = "EXISTS (SELECT 1 FROM game_of_the_month_products WHERE game_of_the_month_products.product_id = products.id)".freeze

    attr_reader :query, :category, :status

    def initialize(params)
      @query    = params[:q].to_s.strip
      @category = params[:cat].to_s
      @status   = STATUSES.include?(params[:status].to_s) ? params[:status].to_s : ""
    end

    def relation
      by_status(by_category(by_query(base))).order(:name)
    end

    def to_params
      { q: query.presence, cat: category.presence, status: status.presence }.compact
    end

    private

    def base
      Product.includes(:category, product_photos: { image_attachment: :blob })
    end

    def by_query(scope)
      return scope if query.blank?

      term = "%#{Product.sanitize_sql_like(query.downcase)}%"
      scope.where("LOWER(products.name) LIKE :term OR products.slug LIKE :term", term: term)
    end

    def by_category(scope)
      return scope if category.blank?

      scope.for_category(category)
    end

    def by_status(scope)
      case status
      when "gotm"      then scope.where(GOTM)
      when "published" then scope.where.not(GOTM).where(published: true)
      when "draft"     then scope.where.not(GOTM).where(published: false)
      else scope
      end
    end
  end
end
