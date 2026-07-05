require "test_helper"

module Catalog
  class SaveProductTest < ActiveSupport::TestCase
    def upload
      Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/sample_product.jpg"), "image/jpeg")
    end

    def graph(**overrides)
      { options: [], tags: [], photos: [], gotm: { enabled: false } }.merge(overrides)
    end

    def save(product, graph_hash, **params)
      Catalog::SaveProduct.call(
        product: product,
        params: {
          name: product.name || "Produto", category_id: categories(:gb_color).id,
          price: "180,00", description: "<p>x</p>", weight_grams: 42, currency: "BRL", published: "1",
          graph: graph_hash.is_a?(String) ? graph_hash : graph_hash.to_json
        }.merge(params)
      )
    end

    test "assigns core attributes and parses the pt-BR price" do
      result = save(Product.new(name: "Novo Jogo"), graph, price: "1.234,50")

      assert result.success?
      product = result.product
      assert_equal 123_450, product.price_cents
      assert_equal 42, product.weight_grams
      assert product.published?
      assert_equal "novo-jogo", product.slug
    end

    test "honours an explicit slug" do
      result = save(Product.new(name: "Nome Longo"), graph, slug: "custom-slug")
      assert_equal "custom-slug", result.product.slug
    end

    test "syncs option groups into positioned rows and drops blanks" do
      product = Product.create!(name: "Base", category: categories(:gb_color), weight_grams: 60)
      save(product, graph(options: [
        { group_name: "Idioma", values: [ { name: "Inglês", weight: 0 }, { name: "", weight: 0 } ] },
        { group_name: "  ", values: [ { name: "Único", weight: 5 } ] }
      ]))

      rows = product.reload.product_options.in_display_order
      assert_equal [ "Inglês", "Único" ], rows.map(&:name)
      assert_equal [ "Idioma", nil ], rows.map(&:group_name)
      assert_equal [ 0, 1 ], rows.map(&:position)
      assert_equal 5, rows.last.weight_delta_grams
    end

    test "reconciles options, removing rows no longer present" do
      product = products(:yellow)
      assert product.product_options.exists?(name: "Português BR")

      save(product, graph(options: [ { group_name: "Versão", values: [ { name: "DX", weight: 2 } ] } ]))

      names = product.reload.product_options.pluck(:name)
      assert_equal [ "DX" ], names
    end

    test "syncs tags, downcasing and de-duplicating, and removes the rest" do
      product = products(:yellow)
      save(product, graph(tags: [ "Zelda", "zelda", "RPG" ]))

      assert_equal %w[rpg zelda], product.reload.tags.map(&:name).sort
    end

    test "attaches a new photo and keeps an existing one, reordered" do
      product = Product.create!(name: "Fotos", category: categories(:gb_color), weight_grams: 60)
      kept = product.product_photos.create!(position: 0, alt_text: "old")

      save(product, graph(photos: [
        { key: "p-0", alt: "capa" },
        { id: kept.id, alt: "segunda" }
      ]), photo_files: { "p-0" => upload })

      photos = product.reload.product_photos.in_display_order
      assert_equal 2, photos.size
      assert photos.first.image.attached?
      assert_equal "capa", photos.first.alt_text
      assert_equal kept.id, photos.second.id
      assert_equal "segunda", photos.second.alt_text
    end

    test "drops photos left out of the graph and ignores missing files or stale ids" do
      product = Product.create!(name: "Limpa", category: categories(:gb_color), weight_grams: 60)
      stale = product.product_photos.create!(position: 0)

      save(product, graph(photos: [ { key: "no-file" }, { id: 999_999 } ]))

      assert_empty product.reload.product_photos
      assert_not ProductPhoto.exists?(stale.id)
    end

    test "enables Jogo do Mês, creating the edition, join and brinde" do
      product = products(:metroid)

      save(product, graph(gotm: {
        enabled: true, year: 2031, month: 8, position: 3, blurb: "Chamada",
        brindes: [ { key: "b-0", caption: "Pôster", kind: "Arte", description: "A3", weight: 7 } ]
      }), brinde_files: { "b-0" => upload })

      join = product.reload.game_of_the_month_products.first
      assert_equal [ 2031, 8 ], [ join.game_of_the_month.year, join.game_of_the_month.month ]
      assert_equal "Chamada", join.blurb
      assert_equal 3, join.position
      assert join.brindes.first.image.attached?
      assert_equal 7, join.brindes.first.weight_grams
    end

    test "moving the edition month reattaches the product and keeps a single join" do
      product = products(:metroid)
      save(product, graph(gotm: { enabled: true, year: 2031, month: 8, brindes: [ { key: "b", caption: "x" } ] }), brinde_files: { "b" => upload })

      save(product, graph(gotm: { enabled: true, year: 2031, month: 9, brindes: [ { key: "b", caption: "x" } ] }), brinde_files: { "b" => upload })

      joins = product.reload.game_of_the_month_products
      assert_equal 1, joins.size
      assert_equal 9, joins.first.game_of_the_month.month
    end

    test "keeps an existing brinde by id and removes the rest" do
      product = products(:metroid)
      save(product, graph(gotm: { enabled: true, year: 2032, month: 1,
        brindes: [ { key: "b-0", caption: "primeiro" }, { key: "b-1", caption: "segundo" } ] }),
        brinde_files: { "b-0" => upload, "b-1" => upload })
      join = product.reload.game_of_the_month_products.first
      keeper = join.brindes.in_display_order.first

      save(product, graph(gotm: { enabled: true, year: 2032, month: 1,
        brindes: [ { id: keeper.id, caption: "renomeado" } ] }))

      brindes = join.reload.brindes
      assert_equal 1, brindes.size
      assert_equal "renomeado", brindes.first.caption
    end

    test "disabling Jogo do Mês destroys the join and its brindes" do
      product = products(:yellow)
      assert product.game_of_the_month_products.exists?

      save(product, graph(gotm: { enabled: false }))

      assert_empty product.reload.game_of_the_month_products
    end

    test "treats malformed graph JSON as empty" do
      product = products(:yellow)
      save(product, "{not json", price: "10,00")

      assert_empty product.reload.product_options
      assert_empty product.tags
    end

    test "returns failure and errors when the product is invalid" do
      result = save(Product.new(name: ""), graph, name: "")

      assert_not result.success?
      assert result.product.errors.of_kind?(:name, :blank)
    end

    test "surfaces a duplicate slug as a taken error" do
      Product.create!(name: "Existente", slug: "dup-slug", category: categories(:gb_color), weight_grams: 60)
      result = save(Product.new(name: "Outro"), graph, slug: "dup-slug")

      assert_not result.success?
      assert result.product.errors.of_kind?(:slug, :taken)
    end
  end
end
