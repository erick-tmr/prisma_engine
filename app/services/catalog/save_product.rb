module Catalog
  class SaveProduct
    Result = Data.define(:product, :success) do
      def success?
        success
      end
    end

    def self.call(product:, params:)
      new(product: product, params: params).call
    end

    def initialize(product:, params:)
      @product = product
      @params  = params
      @graph   = parse_graph(params[:graph])
    end

    def call
      ActiveRecord::Base.transaction { persist! }
      Result.new(product: product, success: true)
    rescue ActiveRecord::RecordInvalid
      Result.new(product: product, success: false)
    rescue ActiveRecord::RecordNotUnique
      product.errors.add(:slug, :taken)
      Result.new(product: product, success: false)
    end

    private

    attr_reader :product, :params, :graph

    def persist!
      assign_core
      product.save!
      sync_options
      sync_tags
      sync_photos
      sync_gotm
      sync_custom_order_form
    end

    def parse_graph(raw)
      JSON.parse(raw.presence || "{}")
    rescue JSON::ParserError
      {}
    end

    def boolean(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def assign_core
      product.assign_attributes(
        name:         params[:name],
        category_id:  params[:category_id],
        description:  params[:description].to_s,
        weight_grams: params[:weight_grams],
        currency:     params[:currency],
        published:    boolean(params[:published]),
        custom_order: boolean(params[:custom_order]),
        price_cents:  HasMoney.parse(params[:price])
      )
      product.slug = params[:slug] if params[:slug].present?
    end

    def sync_options
      kept = flatten_options.map do |attrs|
        option = product.product_options.find_or_initialize_by(
          group_name: attrs[:group_name], name: attrs[:name]
        )
        option.update!(weight_delta_grams: attrs[:weight_delta_grams], position: attrs[:position])
        option.id
      end
      product.product_options.where.not(id: kept).destroy_all
    end

    def flatten_options
      Array(graph["options"]).flat_map { |group| group_option_rows(group) }
                             .each_with_index.map { |attrs, position| attrs.merge(position: position) }
    end

    def group_option_rows(group)
      group_name = group["group_name"].to_s.strip.presence
      Array(group["values"]).filter_map do |value|
        name = value["name"].to_s.strip
        { group_name: group_name, name: name, weight_delta_grams: value["weight"].to_i } if name.present?
      end
    end

    def sync_tags
      names = Array(graph["tags"]).map { |tag| tag.to_s.strip.downcase }.reject(&:blank?).uniq
      product.tags = names.map { |name| Tag.find_or_create_by!(name: name) }
    end

    def sync_photos
      files = params[:photo_files] || {}
      kept = Array(graph["photos"]).each_with_index.filter_map do |meta, index|
        photo = photo_for(meta, files)
        next unless photo

        photo.update!(alt_text: meta["alt"].to_s, position: index)
        photo.id
      end
      product.product_photos.where.not(id: kept).destroy_all
    end

    def photo_for(meta, files)
      if meta["id"]
        product.product_photos.find_by(id: meta["id"])
      elsif files[meta["key"]]
        product.product_photos.new.tap { |photo| photo.image.attach(files[meta["key"]]) }
      end
    end

    def sync_custom_order_form
      submitted = params[:custom_order_form]
      return if submitted.blank?

      form = product.custom_order_form || product.build_custom_order_form
      form.update!(CustomOrderForm::LIMITS.keys.index_with { |field| submitted[field].presence })
    end

    def sync_gotm
      gotm = graph["gotm"] || {}
      return product.game_of_the_month_products.destroy_all unless boolean(gotm["enabled"])

      edition = GameOfTheMonth.find_or_create_by!(year: gotm["year"], month: gotm["month"])
      product.game_of_the_month_products.where.not(game_of_the_month_id: edition.id).destroy_all
      join = product.game_of_the_month_products.find_or_initialize_by(game_of_the_month: edition)
      join.update!(blurb: gotm["blurb"].to_s, position: gotm["position"].to_i)
      sync_brindes(join, gotm["brindes"])
    end

    def sync_brindes(join, brindes)
      files = params[:brinde_files] || {}
      kept = Array(brindes).each_with_index.filter_map do |meta, index|
        brinde = brinde_for(join, meta, files)
        next unless brinde

        brinde.update!(brinde_attributes(meta, index))
        brinde.id
      end
      join.brindes.where.not(id: kept).destroy_all
    end

    def brinde_for(join, meta, files)
      if meta["id"]
        join.brindes.find_by(id: meta["id"])
      elsif files[meta["key"]]
        join.brindes.new.tap { |brinde| brinde.image.attach(files[meta["key"]]) }
      end
    end

    def brinde_attributes(meta, index)
      {
        caption:      meta["caption"].to_s,
        kind:         meta["kind"].to_s,
        description:  meta["description"].to_s,
        weight_grams: meta["weight"].to_i,
        position:     index
      }
    end
  end
end
