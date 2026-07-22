require "test_helper"

module Admin
  class CatalogPresenterTest < ActiveSupport::TestCase
    setup { @presenter = Admin::CatalogPresenter.new }

    test "lists every product ordered by name" do
      assert_equal Product.order(:name).pluck(:name), @presenter.products.map(&:name)
    end

    test "exposes categories for the filter as [name, slug] pairs" do
      assert_includes @presenter.categories, [ "Game Boy Color", "game-boy-color" ]
    end

    test "counts distinct option groups per product" do
      assert_equal 2, @presenter.option_group_count(products(:yellow))
      assert_equal 0, @presenter.option_group_count(products(:metroid))
    end

    test "flags status as gotm, published or draft" do
      assert_equal :gotm, @presenter.status(products(:yellow))
      assert_equal :published, @presenter.status(products(:game_box))
      assert_equal :draft, @presenter.status(products(:hidden))
    end
  end
end
