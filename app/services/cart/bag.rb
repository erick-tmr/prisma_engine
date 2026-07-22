module Cart
  # Cookie-backed shopping cart. The bag is a thin, frozen-time view over the
  # raw items hash that lives in `cookies.signed[:cart]`. Lines are hydrated on
  # demand against the live Product / ProductOption rows, so price changes and
  # option renames propagate without rewriting the cookie.
  #
  # Cookie payload shape (versioned so we can evolve later without exploding
  # everyone's existing cart):
  #
  #   { "v" => 1, "items" => [{ "id" => "<8 chars>", "p" => 42, "q" => 1, "o" => [3, 7],
  #                             "r" => { "g" => "<game>", "n" => "<notes>" } }] }
  #
  # A line's `id` is a stable random token allocated at add-time; it survives
  # option edits so the in-cart variant editor can swap `o` without losing the
  # line. `r` is the optional made-to-order request (game + notes); it is absent
  # on regular lines and its `n` is dropped when blank.
  #
  # Reek's TooManyMethods threshold (15) is too tight for a service object that
  # owns the full cart vocabulary (add/update/remove × hydrated reads × cookie
  # serialization × hygiene. Splitting it across collaborators would add
  # indirection without resolving the actual god-class smell.
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

    # Drops items whose product is missing/unpublished or whose option ids no
    # longer belong to the product. Returns true when anything was removed so
    # the caller can rewrite the cookie + flash a notice.
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

    # Total package weight for shipping quotes. The brindes contribution scales
    # by line quantity per the spec: a customer buying 2× a GOTM game gets 2×
    # that game's own brindes mass. Caller supplies each GOTM product's brindes
    # weight keyed by product id, so the bag stays AR-free beyond what `lines`
    # already loads.
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
