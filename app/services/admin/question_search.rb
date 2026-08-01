module Admin
  class QuestionSearch
    CHIP_STATUSES = {
      "open" => "awaiting_answer",
      "draft" => "draft",
      "answered" => "answered",
      "archived" => "archived",
      "spam" => "spam"
    }.freeze
    CHIPS = (CHIP_STATUSES.keys + [ "all" ]).freeze
    DEFAULT_CHIP = "open".freeze
    SORTS = %w[oldest newest].freeze
    DEFAULT_SORT = "oldest".freeze

    attr_reader :query, :chip, :product, :sort

    def initialize(params)
      @query   = params[:q].to_s.strip
      @chip    = CHIPS.include?(params[:status].to_s) ? params[:status].to_s : DEFAULT_CHIP
      @product = params[:produto].to_s[/\A\d+\z/].to_s
      @sort    = SORTS.include?(params[:sort].to_s) ? params[:sort].to_s : DEFAULT_SORT
    end

    def relation
      sorted(by_product(by_query(by_chip(base))))
    end

    def to_params
      {
        q: query.presence,
        status: (chip unless chip == DEFAULT_CHIP),
        produto: product.presence,
        sort: (sort unless sort == DEFAULT_SORT)
      }.compact
    end

    def chip_counts
      @chip_counts ||= begin
        totals = Question.group(:status).count
        CHIPS.index_with { |name| name == "all" ? totals.values.sum : totals.fetch(CHIP_STATUSES[name], 0) }
      end
    end

    def products
      Product.where(id: Question.select(:product_id)).order(:name)
    end

    private

    def base
      Question.includes(:user, product: :category)
    end

    def by_chip(scope)
      status = CHIP_STATUSES[chip]
      status ? scope.where(status: status) : scope
    end

    def by_query(scope)
      return scope if query.blank?

      term = "%#{Question.sanitize_sql_like(query.downcase)}%"
      scope.joins(:user).where(
        "LOWER(questions.body) LIKE :term OR LOWER(users.full_name) LIKE :term OR LOWER(users.email) LIKE :term",
        term: term
      )
    end

    def by_product(scope)
      return scope if product.blank?

      scope.where(product_id: product)
    end

    def sorted(scope)
      sort == "oldest" ? scope.oldest_first : scope.newest_first
    end
  end
end
