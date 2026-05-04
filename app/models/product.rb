class Product
  DATA_PATH = Rails.root.join("config", "products.yml")

  CATEGORY_LABELS = {
    "game-boy-classic" => "Game Boy Classic",
    "game-boy-color"   => "Game Boy Color",
    "other"            => "Outros"
  }.freeze

  CATEGORY_IDS = {
    "game-boy-classic" => 351512,
    "game-boy-color"   => 354342
  }.freeze

  attr_reader :id, :short_id, :slug, :title, :price_brl, :image, :category

  def initialize(attrs)
    @id        = attrs.fetch("id")
    @short_id  = attrs.fetch("short_id")
    @slug      = attrs.fetch("slug")
    @title     = attrs.fetch("title")
    @price_brl = attrs["price_brl"].to_f
    @image     = attrs["image"]
    @category  = attrs["category"]
  end

  def category_label
    CATEGORY_LABELS[category] || CATEGORY_LABELS["other"]
  end

  def to_param
    id
  end

  def price_formatted
    return "Sob consulta" if price_brl.zero?
    "R$ %0.2f" % price_brl
  end

  class << self
    def all
      @all ||= load_from_yaml
    end

    def reload!
      @all = load_from_yaml
    end

    def find(id)
      all.find { |p| p.id == id }
    end

    def find_by_slug_and_id(slug, id)
      all.find { |p| p.slug == slug && p.id == id }
    end

    def for_category(category)
      all.select { |p| p.category == category }
    end

    def featured(limit = 8)
      all.reject { |p| p.title.start_with?("- ") }.first(limit)
    end

    private

    def load_from_yaml
      raw = YAML.safe_load_file(DATA_PATH)
      raw.fetch("products", []).map { |attrs| new(attrs) }
    end
  end
end
