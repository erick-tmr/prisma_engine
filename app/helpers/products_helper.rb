module ProductsHelper
  DESCRIPTION_TAGS = %w[p br ul ol li strong em b i a h3 h4 h5].freeze
  DESCRIPTION_ATTRIBUTES = %w[href target rel].freeze
  HEADING_DEMOTIONS = { "h4" => "h5", "h3" => "h4", "h2" => "h3" }.freeze
  QUESTIONS_PAGE_SIZE = 4

  def product_description(html)
    with_targets = demote_headings(html.to_s).gsub(/<a\b/i, '<a target="_blank" rel="noopener noreferrer"')
    sanitize(with_targets, tags: DESCRIPTION_TAGS, attributes: DESCRIPTION_ATTRIBUTES)
  end

  def product_cards_cache_key(products)
    [ products, products.map(&:image) ]
  end

  private

  def demote_headings(html)
    HEADING_DEMOTIONS.reduce(html) do |markup, (from, to)|
      markup.gsub(%r{<(/?)#{from}\b}i) { "<#{Regexp.last_match(1)}#{to}" }
    end
  end
end
