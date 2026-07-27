require "test_helper"

module Admin
  class CatalogSearchTest < ActiveSupport::TestCase
    def names(params)
      CatalogSearch.new(params).relation.map(&:name)
    end

    test "it lists every product ordered by name" do
      assert_equal Product.order(:name).pluck(:name), names({})
    end

    test "the query matches the product name case-insensitively" do
      product = products(:metroid)
      assert_includes names({ q: product.name.upcase }), product.name
      assert_empty names({ q: "zzzz-no-such-thing" })
    end

    test "the accent-stripped slug still answers an unaccented query" do
      accented = Product.create!(category: categories(:gb_color), name: "Pokémon Crystal",
                                 price_cents: 1000, weight_grams: 20)

      assert_equal "pokemon-crystal", accented.slug
      assert_includes names({ q: "pokemon" }), accented.name,
                      "the unaccented slug is the only thing that can match an unaccented query"
      assert_includes names({ q: "pokémon" }), accented.name,
                      "the accented name still matches directly"
    end

    test "a percent sign in the query is matched literally" do
      assert_empty names({ q: "%" })
    end

    test "the category filter matches the slug" do
      assert_equal Product.for_category("game-boy-color").order(:name).pluck(:name),
                   names({ cat: "game-boy-color" })
      assert_empty names({ cat: "no-such-category" })
    end

    test "game of the month shadows published and draft" do
      featured = products(:yellow)

      assert_includes names({ status: "gotm" }), featured.name
      assert_not_includes names({ status: "published" }), featured.name
      assert_not_includes names({ status: "draft" }), featured.name
    end

    test "published and draft split the rest of the catalog between them" do
      assert_equal names({}).size, names({ status: "published" }).size +
                                   names({ status: "draft" }).size +
                                   names({ status: "gotm" }).size
      assert_includes names({ status: "draft" }), products(:hidden).name
    end

    test "an unknown status is ignored rather than emptying the list" do
      assert_equal names({}), names({ status: "whatever" })
    end

    test "filters combine" do
      product = products(:yellow)
      assert_includes names({ q: product.name, cat: product.category.slug, status: "gotm" }), product.name
      assert_empty names({ q: product.name, status: "draft" })
    end

    test "to_params keeps only what was set" do
      assert_empty CatalogSearch.new({}).to_params
      assert_equal({ q: "zelda", cat: "game-boy-color", status: "draft" },
                   CatalogSearch.new({ q: " zelda ", cat: "game-boy-color", status: "draft" }).to_params)
    end
  end
end
