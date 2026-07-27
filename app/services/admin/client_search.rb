module Admin
  class ClientSearch
    SORT_KEYS = %w[name cpf city since orders status].freeze
    DEFAULT_SORT = "name".freeze

    SITUATION = <<~SQL.squish.freeze
      CASE WHEN users.locked_at IS NOT NULL THEN 'locked'
           WHEN users.confirmed_at IS NULL THEN 'pending'
           ELSE 'active' END
    SQL

    # One row per user even if the "single default address" rule ever drifts,
    # which no database constraint enforces today.
    DEFAULT_ADDRESS = <<~SQL.squish.freeze
      LEFT JOIN LATERAL (
        SELECT addresses.city, addresses.state
        FROM addresses
        WHERE addresses.user_id = users.id AND addresses."default"
        ORDER BY addresses.id
        LIMIT 1
      ) default_address ON TRUE
    SQL

    ORDER_COUNT = "(SELECT COUNT(*) FROM orders WHERE orders.user_id = users.id)".freeze

    attr_reader :query, :sort, :direction

    def initialize(params)
      @query     = params[:q].to_s.strip
      @sort      = SORT_KEYS.include?(params[:sort].to_s) ? params[:sort].to_s : DEFAULT_SORT
      @direction = %w[asc desc].include?(params[:dir].to_s) ? params[:dir].to_s : "asc"
    end

    def relation
      filtered.order(order_expression => direction, full_name: :asc)
    end

    def to_params
      {
        q: query.presence,
        sort: (sort unless sort == DEFAULT_SORT),
        dir: (direction unless direction == "asc")
      }.compact
    end

    private

    def filtered
      by_query(base)
    end

    def base
      User.where(admin: false)
          .joins(DEFAULT_ADDRESS)
          .select(
            "users.*",
            "default_address.city AS default_city",
            "default_address.state AS default_state",
            "#{ORDER_COUNT} AS orders_count",
            "#{SITUATION} AS situation"
          )
    end

    # Matches the columns the operator can see, except phone, which the list
    # renders but has never searched. City and UF match as "city/uf".
    def by_query(scope)
      return scope if query.blank?

      term = "%#{User.sanitize_sql_like(query.downcase)}%"
      scope.where(
        "users.full_name ILIKE :term OR users.email ILIKE :term OR users.cpf LIKE :term " \
        "OR LOWER(COALESCE(default_address.city, '') || '/' || COALESCE(default_address.state, '')) LIKE :term",
        term: term
      )
    end

    def order_expression
      case sort
      when "cpf"    then Arel.sql("users.cpf")
      when "city"   then Arel.sql("default_address.city")
      when "since"  then Arel.sql("users.created_at")
      when "orders" then Arel.sql(ORDER_COUNT)
      when "status" then Arel.sql(SITUATION)
      else Arel.sql("users.full_name")
      end
    end
  end
end
