require "test_helper"

module Admin
  class ProductFormPresenterTest < ActiveSupport::TestCase
    test "build_new seeds the design defaults" do
      product = Admin::ProductFormPresenter.build_new

      assert product.new_record?
      assert_equal categories(:gb_color), product.category
      assert_equal 60, product.weight_grams
      assert_equal 19_000, product.price_cents
      assert product.published
      assert_equal Admin::ProductFormPresenter::DEFAULT_DESCRIPTION, product.description
    end

    test "formats the price input and flags the default description" do
      presenter = Admin::ProductFormPresenter.new(Admin::ProductFormPresenter.build_new)

      assert presenter.new_record?
      assert_equal "190,00", presenter.price_input
      assert presenter.description_default?
    end

    test "a new product's graph carries the default Idioma group and blank collections" do
      graph = JSON.parse(Admin::ProductFormPresenter.new(Admin::ProductFormPresenter.build_new).graph_json)

      assert_equal [ "Idioma" ], graph["options"].map { |group| group["group_name"] }
      assert_equal Admin::ProductFormPresenter::DEFAULT_LANGUAGES, graph["options"].first["values"].map { |value| value["name"] }
      assert_empty graph["tags"]
      assert_empty graph["photos"]
      assert_equal false, graph["gotm"]["enabled"]
    end

    test "an existing product serializes its options, tags and gotm module" do
      presenter = Admin::ProductFormPresenter.new(products(:yellow))
      graph = JSON.parse(presenter.graph_json)

      assert_equal %w[Idioma Caixa], graph["options"].map { |group| group["group_name"] }
      assert_includes graph["tags"], "pokemon"
      assert graph["gotm"]["enabled"]
      assert_equal 2, graph["gotm"]["brindes"].size
      assert_not presenter.description_default?
      assert_equal "180,00", presenter.price_input
    end

    test "an existing product with no options serializes an empty group list" do
      graph = JSON.parse(Admin::ProductFormPresenter.new(products(:metroid)).graph_json)
      assert_empty graph["options"]
    end

    test "serializes the url of an attached photo" do
      product = products(:game_box)
      photo = product.product_photos.create!(position: 0, alt_text: "capa")
      photo.image.attach(io: File.open(file_fixture("sample_product.jpg")), filename: "s.jpg", content_type: "image/jpeg")

      graph = JSON.parse(Admin::ProductFormPresenter.new(product).graph_json)
      assert graph["photos"].first["url"].present?
    end

    test "echoes the submitted graph verbatim on re-render" do
      presenter = Admin::ProductFormPresenter.new(Product.new, submitted_graph: '{"tags":["kept"]}')
      assert_equal '{"tags":["kept"]}', presenter.graph_json
    end

    test "provides select options for categories, currencies, months and years" do
      presenter = Admin::ProductFormPresenter.new(Product.new)

      assert_includes presenter.categories, [ "Game Boy Color", categories(:gb_color).id ]
      assert_equal "BRL", presenter.currencies.first.last
      assert_equal 12, presenter.months.size
      assert_equal [ Time.current.year - 1, Time.current.year, Time.current.year + 1 ], presenter.years
    end
  end
end
