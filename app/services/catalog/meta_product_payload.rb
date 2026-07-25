module Catalog
  class MetaProductPayload
    DEFAULTS = { brand: "Prisma Games", condition: "new", availability: "in stock" }.freeze
    GOOGLE_CATEGORY = { game: "Toys & Games > Games", other: "Toys & Games" }.freeze
    LIMITS = { title: 200, description: 9_999, additional_images: 10 }.freeze
    BLOCK_BOUNDARY = %r{</p>|<br\s*/?>|</div>|</li>|</h[1-6]>}i

    def self.call(product)
      new(product).to_h
    end

    def initialize(product)
      @product = product
    end

    def to_h
      images = ordered_image_urls
      {
        title: product.name.to_s.truncate(LIMITS[:title]),
        description: description,
        availability: DEFAULTS[:availability],
        condition: DEFAULTS[:condition],
        brand: DEFAULTS[:brand],
        price: formatted_price,
        link: link,
        image_link: images.first,
        additional_image_link: images.drop(1).take(LIMITS[:additional_images]),
        google_product_category: google_category,
        identifier_exists: false
      }
    end

    private

    attr_reader :product

    def formatted_price
      format("%.2f %s", product.price_cents / 100.0, product.currency)
    end

    def description
      spaced = product.description.to_s.gsub(BLOCK_BOUNDARY, " ")
      text = CGI.unescapeHTML(ActionController::Base.helpers.strip_tags(spaced)).squish
      (text.presence || product.name.to_s).truncate(LIMITS[:description])
    end

    def link
      Rails.application.routes.url_helpers.product_url(product, **url_options)
    end

    def url_options
      Rails.application.config.action_mailer.default_url_options
    end

    def ordered_image_urls
      product.product_photos.in_display_order.filter_map do |photo|
        Storefront::ImageSource.call(photo.image) if photo.image.attached?
      end
    end

    def google_category
      product.category.slug == "miscelanea" ? GOOGLE_CATEGORY[:other] : GOOGLE_CATEGORY[:game]
    end
  end
end
