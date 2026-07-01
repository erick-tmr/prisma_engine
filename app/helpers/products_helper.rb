module ProductsHelper
  DESCRIPTION_TAGS = %w[p br ul ol li strong em b i a].freeze
  DESCRIPTION_ATTRIBUTES = %w[href target rel].freeze

  def product_description(html)
    with_targets = html.to_s.gsub(/<a\b/i, '<a target="_blank" rel="noopener noreferrer"')
    sanitize(with_targets, tags: DESCRIPTION_TAGS, attributes: DESCRIPTION_ATTRIBUTES)
  end
end
