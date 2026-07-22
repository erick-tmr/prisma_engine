module Cart
  # :reek:TooManyMethods
  class Bag
    VERSION = 1
    QUANTITY_RANGE = 1..99
    ID_LENGTH = 8
    GAME_MAX_LENGTH = 120
    NOTES_MAX_LENGTH = 280

    def self.from_cookie(payload)
      raw = payload.is_a?(Hash) && payload["v"] == VERSION ? Array(payload["items"]) : []
      new(raw.filter_map { |row| normalize_row(row) })
    end

    def self.normalize_row(row)
      return nil unless row.is_a?(Hash)
      id         = row["id"].to_s
      product_id = row["p"].to_i
      quantity   = row["q"].to_i
      return nil if id.empty? || product_id <= 0 || quantity <= 0
      base = { "id" => id, "p" => product_id, "q" => quantity, "o" => Array(row["o"]).map(&:to_i).sort }
      merge_request(base, row["r"])
    end
    private_class_method :normalize_row

    def self.merge_request(base, raw)
      request = normalize_request(raw)
      request ? base.merge("r" => request) : base
    end
    private_class_method :merge_request

    def self.normalize_request(raw)
      return nil unless raw.is_a?(Hash)
      game = raw["g"].to_s.strip[0, GAME_MAX_LENGTH]
      return nil if game.empty?
      notes = raw["n"].to_s.strip[0, NOTES_MAX_LENGTH]
      request = { "g" => game }
      notes.empty? ? request : request.merge("n" => notes)
    end

    attr_reader :items

    def initialize(items = [])
      @items = items
    end

    def to_cookie
      { "v" => VERSION, "items" => items }
    end

    def empty?
      items.empty?
    end

    def total_quantity
      items.sum { |item| item["q"] }
    end

    def add(product:, quantity:, option_ids: [], request: nil)
      qty = clamp(quantity)
      ids = Array(option_ids).map(&:to_i).sort
      req = self.class.normalize_request("g" => request&.dig(:game), "n" => request&.dig(:notes))
      existing = items.find { |item| item["p"] == product.id && item["o"] == ids && item["r"] == req }
      if existing
        existing["q"] = clamp(existing["q"] + qty)
      else
        items << new_row(product, qty, ids, req)
      end
      self
    end

    def update_quantity(line_id, quantity)
      item = find_item(line_id)
      item["q"] = clamp(quantity) if item
      self
    end

    def update_options(line_id, option_ids)
      item = find_item(line_id)
      item["o"] = Array(option_ids).map(&:to_i).sort if item
      self
    end

    def remove(line_id)
      items.reject! { |item| item["id"] == line_id.to_s }
      self
    end

    def cleanup!
      return false if items.empty?
      kept_ids = lines.map(&:id)
      before = items.length
      @items = items.select { |item| kept_ids.include?(item["id"]) }
      items.length != before
    end

    def lines
      return [] if items.empty?
      products = lookup_products
      options  = lookup_options
      items.filter_map { |item| build_line(item, products, options) }
    end

    def subtotal_cents
      lines.sum(&:line_total_cents)
    end

    def subtotal_formatted
      HasMoney.format(subtotal_cents)
    end

    def total_weight_grams(gotm_brindes_weight_by_product_id:)
      lines.sum do |line|
        extra = gotm_brindes_weight_by_product_id.fetch(line.product.id, 0)
        (line.weight_grams + extra) * line.quantity
      end
    end

    private

    def lookup_products
      Product.where(id: items.map { |item| item["p"] }, published: true).index_by(&:id)
    end

    def lookup_options
      ProductOption.where(id: items.flat_map { |item| item["o"] }).index_by(&:id)
    end

    def build_line(item, products_by_id, options_by_id)
      product = products_by_id[item["p"]]
      return nil unless product
      chosen = item["o"].map { |option_id| options_by_id[option_id] }
      return nil if chosen.any?(&:nil?) || chosen.any? { |opt| opt.product_id != product.id }
      Line.new(id: item["id"], product: product, quantity: item["q"], options: chosen, request: item["r"])
    end

    def find_item(line_id)
      items.find { |item| item["id"] == line_id.to_s }
    end

    def clamp(qty)
      qty.to_i.clamp(QUANTITY_RANGE)
    end

    def new_row(product, qty, ids, req)
      row = { "id" => SecureRandom.alphanumeric(ID_LENGTH), "p" => product.id, "q" => qty, "o" => ids }
      row["r"] = req if req
      row
    end
  end
end
