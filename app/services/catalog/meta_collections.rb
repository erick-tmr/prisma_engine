module Catalog
  class MetaCollections
    GAME_OF_THE_MONTH = "Jogos do Mês".freeze

    def self.call
      new.call
    end

    def call
      return unless Meta::Api.shops_configured?

      existing = Meta::Api::ProductSets.list.to_h { |set| [ set["name"], set["id"] ] }
      specs.each do |name, filter|
        publish(name, filter, existing[name])
      rescue Meta::Api::EmptyProductSetError
        next
      end
    end

    private

    def specs
      category_specs.merge(GAME_OF_THE_MONTH => game_of_the_month_filter)
    end

    def category_specs
      sellable_category_names.index_with { |name| { "product_type" => { "eq" => name } } }
    end

    def sellable_category_names
      Category.joins(:products)
              .where(products: { published: true })
              .where("products.price_cents > 0")
              .distinct
              .pluck(:name)
    end

    def game_of_the_month_filter
      { "retailer_id" => { "is_any" => GameOfTheMonth.current_product_ids.map(&:to_s) } }
    end

    def publish(name, filter, id)
      if id
        Meta::Api::ProductSets.update(id, filter: filter)
      else
        Meta::Api::ProductSets.create(name: name, filter: filter, shop_id: Meta::Api.shop_id)
      end
    end
  end
end
