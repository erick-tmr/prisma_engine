module Admin
  class ProductFormPresenter
    DEFAULT_DESCRIPTION = <<~HTML.strip
      <p>Cartucho reproduzido pela Prisma Games, no Brasil, com placa própria (Prisma v0.6) testada uma a uma. O save fica gravado em memória FRAM, que não precisa de bateria, e seu progresso dura por anos, sem risco de perder os arquivos.</p>
      <p>Já vem completo, com estojo rígido e etiqueta em padrão US, compatível com a linha Game Boy. Você escolhe o idioma da ROM nas opções acima, e cada unidade é testada individualmente antes do envio.</p>
    HTML
    DEFAULT_LANGUAGES = [ "Português BR", "Inglês", "Japonês" ].freeze
    DEFAULT_WEIGHT = 60
    CURRENCIES = [ [ "BRL · Real (R$)", "BRL" ], [ "USD · Dólar (US$)", "USD" ], [ "EUR · Euro (€)", "EUR" ] ].freeze
    PUBLISH_AT_FORMAT = "%Y-%m-%dT%H:%M".freeze

    def self.build_new
      Product.new(
        category:     default_category,
        weight_grams: DEFAULT_WEIGHT,
        price_cents:  19_000,
        currency:     "BRL",
        published:    true,
        custom_order: false,
        description:  DEFAULT_DESCRIPTION
      )
    end

    def self.default_category
      Category.find_by(slug: "game-boy-color") || Category.order(:name).first
    end

    def initialize(product, submitted_graph: nil)
      @product = product
      @submitted_graph = submitted_graph
    end

    attr_reader :product

    def new_record?
      product.new_record?
    end

    def price_input
      format("%.2f", product.price_cents.to_i / 100.0).tr(".", ",")
    end

    def description_default?
      new_record? || product.description == DEFAULT_DESCRIPTION
    end

    def default_description
      DEFAULT_DESCRIPTION
    end

    def custom_order_form
      product.custom_order_text
    end

    def graph_json
      @submitted_graph.presence || build_graph.to_json
    end

    def categories
      Category.order(:name).pluck(:name, :id)
    end

    def currencies
      CURRENCIES
    end

    def months
      I18n.t("date.month_names").drop(1).each_with_index.map { |name, index| [ name, index + 1 ] }
    end

    def years
      year = Time.current.year
      [ year - 1, year, year + 1 ]
    end

    def current_edition
      format("%04d-%02d", Time.current.year, Time.current.month)
    end

    private

    def build_graph
      {
        "options" => option_groups,
        "tags"    => product.tags.map(&:name),
        "photos"  => photos,
        "gotm"    => gotm
      }
    end

    def option_groups
      groups = product.product_options.in_display_order.group_by(&:group_name).map do |group_name, options|
        { "group_name" => group_name, "values" => option_values(options) }
      end
      groups.presence || default_option_groups
    end

    def option_values(options)
      options.map { |option| { "name" => option.name, "weight" => option.weight_delta_grams } }
    end

    def default_option_groups
      return [] unless new_record?

      [ { "group_name" => "Idioma", "values" => DEFAULT_LANGUAGES.map { |lang| { "name" => lang, "weight" => 0 } } } ]
    end

    def photos
      product.product_photos.in_display_order.map do |photo|
        { "id" => photo.id, "url" => image_url(photo.image), "alt" => photo.alt_text }
      end
    end

    def gotm
      join = product.game_of_the_month_products.first
      return blank_gotm unless join

      edition = join.game_of_the_month
      {
        "enabled" => true, "year" => edition.year, "month" => edition.month,
        "publish_at" => edition.publish_at.strftime(PUBLISH_AT_FORMAT),
        "position" => join.position, "blurb" => join.blurb.to_s, "brindes" => brindes(join)
      }
    end

    def blank_gotm
      {
        "enabled" => false, "year" => Time.current.year, "month" => Time.current.month,
        "publish_at" => default_publish_at,
        "position" => 0, "blurb" => "", "brindes" => []
      }
    end

    def default_publish_at
      Time.zone.local(Time.current.year, Time.current.month, 1).strftime(PUBLISH_AT_FORMAT)
    end

    def brindes(join)
      join.brindes.in_display_order.map do |brinde|
        {
          "id" => brinde.id, "url" => image_url(brinde.image), "caption" => brinde.caption.to_s,
          "kind" => brinde.kind.to_s, "description" => brinde.description.to_s, "weight" => brinde.weight_grams
        }
      end
    end

    def image_url(attachment)
      attachment.attached? ? Storefront::ImageSource.call(attachment) : nil
    end
  end
end
