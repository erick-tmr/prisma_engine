module Admin
  class OrderSearch
    SORT_KEYS = %w[client date total status].freeze
    DEFAULT_SORT = "date".freeze
    ASCENDING_BY_DEFAULT = %w[client].freeze

    attr_reader :query, :statuses, :from, :to, :sort, :direction

    def initialize(params)
      @query     = params[:q].to_s.strip
      @statuses  = Array(params[:status]).map(&:to_s) & Order::STATUSES
      @from      = parse_date(params[:de])
      @to        = parse_date(params[:ate])
      @sort      = SORT_KEYS.include?(params[:sort].to_s) ? params[:sort].to_s : DEFAULT_SORT
      @direction = direction_for(params[:dir])
    end

    def relation
      filtered.order(order_expression => direction, created_at: :desc)
    end

    def total_cents
      filtered.sum(:total_cents)
    end

    def to_params
      {
        q: query.presence,
        status: statuses.presence,
        de: iso(from),
        ate: iso(to),
        sort: (sort unless sort == DEFAULT_SORT),
        dir: (direction unless default_direction?)
      }.compact
    end

    def period_params
      { de: iso(from), ate: iso(to) }.compact
    end

    def filtered?
      query.present? || statuses.any? || from || to
    end

    private

    def filtered
      by_period(by_status(by_query(base)))
    end

    def base
      Order.joins(:user).preload(:user, :order_items, :shipment)
    end

    def by_query(scope)
      return scope if query.blank?

      term = "%#{Order.sanitize_sql_like(query)}%"
      scope.where("users.full_name ILIKE :term OR orders.number ILIKE :term", term: term)
    end

    def by_status(scope)
      return scope.where.not(status: "merged") if statuses.empty?

      scope.where(status: statuses)
    end

    def by_period(scope)
      return scope unless from || to

      scope.where(created_at: lower_bound..upper_bound)
    end

    def lower_bound
      from&.in_time_zone&.beginning_of_day
    end

    def upper_bound
      to&.in_time_zone&.end_of_day
    end

    def order_expression
      case sort
      when "client" then Arel.sql("LOWER(users.full_name)")
      when "total"  then Arel.sql("orders.total_cents")
      when "status" then status_position
      else Arel.sql("orders.created_at")
      end
    end

    def status_position
      Arel.sql(
        Order.sanitize_sql_array([ "array_position(ARRAY[?]::varchar[], orders.status)", Order::STATUSES ])
      )
    end

    def direction_for(raw)
      %w[asc desc].include?(raw.to_s) ? raw.to_s : default_direction
    end

    def default_direction
      ASCENDING_BY_DEFAULT.include?(sort) ? "asc" : "desc"
    end

    def default_direction?
      direction == default_direction
    end

    def parse_date(raw)
      value = raw.to_s
      return if value.blank?

      Date.iso8601(value)
    rescue ArgumentError
      nil
    end

    def iso(date)
      date&.iso8601
    end
  end
end
