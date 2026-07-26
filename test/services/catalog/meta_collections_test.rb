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

    test "creates a set per non-empty category plus the highlight, skipping empty categories" do
      created = []

      with_shops do
        Meta::Api::ProductSets.stub(:list, -> { [] }) do
          Meta::Api::ProductSets.stub(:create, ->(name:, filter:, shop_id:) { created << [ name, filter, shop_id ] }) do
            Catalog::MetaCollections.call
          end
        end
      end

      names = created.map(&:first)
      assert_includes names, "Game Boy Color"
      assert_includes names, "Jogos do Mês"
      assert_not_includes names, "Game Boy Advance"
      game_boy_color = created.find { |name, _filter, _shop| name == "Game Boy Color" }
      assert_equal({ "product_type" => { "eq" => "Game Boy Color" } }, game_boy_color[1])
      assert_equal "shop-1", game_boy_color[2]
    end

    test "skips a collection Meta rejects as empty and keeps going" do
      created = []
      create = lambda do |name:, filter:, shop_id:|
        raise Meta::Api::EmptyProductSetError, "empty" if name == "Pedidos de Jogos"

        created << name
      end

      with_shops do
        Meta::Api::ProductSets.stub(:list, -> { [] }) do
          Meta::Api::ProductSets.stub(:create, create) do
            Catalog::MetaCollections.call
          end
        end
      end

      assert_not_includes created, "Pedidos de Jogos"
      assert_includes created, "Game Boy Color"
    end

    test "updates an existing set by name instead of creating it" do
      updated = []
      created = []

      with_shops do
        Meta::Api::ProductSets.stub(:list, -> { [ { "name" => "Game Boy Color", "id" => "existing-1" } ] }) do
          Meta::Api::ProductSets.stub(:update, ->(id, filter:) { updated << id }) do
            Meta::Api::ProductSets.stub(:create, ->(name:, filter:, shop_id:) { created << name }) do
              Catalog::MetaCollections.call
            end
          end
        end
      end

      assert_includes updated, "existing-1"
      assert_not_includes created, "Game Boy Color"
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
