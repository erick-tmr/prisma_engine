module Cart
  # Hydrated view of one cart line: the product, the quantity, and the
  # chosen ProductOption rows. Weight is derived live so option weight
  # deltas in the catalog reach the cart on the next render without a
  # cookie rewrite.
  class Line
    def initialize(id:, product:, quantity:, options:, request: nil)
      @id = id
      @product = product
      @quantity = quantity
      @options = options
      @request = request
    end

    attr_reader :id, :product, :quantity, :options

    def requested_game
      @request&.dig("g")
    end

    def request_notes
      @request&.dig("n")
    end

    def selected_for(group_name)
      options.find { |opt| opt.group_name == group_name }
    end

    def weight_grams
      product.weight_grams + options.sum(&:weight_delta_grams)
    end

    def unit_price_cents
      product.price_cents
    end

    def line_total_cents
      unit_price_cents * quantity
    end

    def unit_price_formatted
      HasMoney.format(unit_price_cents)
    end

    def line_total_formatted
      HasMoney.format(line_total_cents)
    end
  end
end
