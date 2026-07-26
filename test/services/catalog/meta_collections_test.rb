require "test_helper"

module Catalog
  class MetaCollectionsTest < ActiveSupport::TestCase
    def with_shops(&block)
      Meta::Api.stub(:shops_configured?, true) do
        Meta::Api.stub(:shop_id, "shop-1", &block)
      end
    end

    test "does nothing when shops are not configured" do
      assert_nothing_raised { Catalog::MetaCollections.call }
    end

    test "creates a set for each collection when none exist yet" do
      created = []
      create_stub = ->(name:, filter:, shop_id:) { created << [ name, filter, shop_id ] }

      with_shops do
        Meta::Api::ProductSets.stub(:list, -> { [] }) do
          Meta::Api::ProductSets.stub(:create, create_stub) do
            Catalog::MetaCollections.call
          end
        end
      end

      assert_equal 5, created.size
      game_boy = created.find { |name, _filter, _shop| name == "Game Boy" }
      assert_equal({ "product_type" => { "eq" => "Game Boy Classic" } }, game_boy[1])
      assert_equal "shop-1", game_boy[2]
      assert_includes created.map(&:first), "Jogos do Mês"
    end

    test "updates an existing set by name instead of creating it" do
      updated = []
      created = []

      with_shops do
        Meta::Api::ProductSets.stub(:list, -> { [ { "name" => "Game Boy", "id" => "existing-1" } ] }) do
          Meta::Api::ProductSets.stub(:update, ->(id, filter:) { updated << id }) do
            Meta::Api::ProductSets.stub(:create, ->(name:, filter:, shop_id:) { created << name }) do
              Catalog::MetaCollections.call
            end
          end
        end
      end

      assert_equal [ "existing-1" ], updated
      assert_not_includes created, "Game Boy"
    end

    test "the Game of the Month set filters on the current edition product ids" do
      product = products(:yellow)
      GameOfTheMonth.current.destroy_all
      edition = GameOfTheMonth.create!(year: Time.current.year, month: Time.current.month)
      edition.game_of_the_month_products.create!(product: product, position: 0)
      captured = {}

      with_shops do
        Meta::Api::ProductSets.stub(:list, -> { [] }) do
          Meta::Api::ProductSets.stub(:create, ->(name:, filter:, shop_id:) { captured[name] = filter }) do
            Catalog::MetaCollections.call
          end
        end
      end

      assert_equal({ "retailer_id" => { "is_any" => [ product.id.to_s ] } }, captured["Jogos do Mês"])
    end
  end
end
