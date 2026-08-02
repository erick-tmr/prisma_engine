require "test_helper"

module Admin
  class PageTest < ActiveSupport::TestCase
    test "it counts the relation and slices the requested page" do
      page = Page.new(Product.order(:id), 1, per: 2)

      assert_equal Product.count, page.total
      assert_equal 2, page.rows.size
      assert_equal Product.order(:id).first(2).map(&:id), page.rows.map(&:id)
    end

    test "it reports the page size it was built with" do
      assert_equal 8, Page.new(Product.order(:id), 1, per: 8).per
      assert_equal Page::PER, Page.new(Product.order(:id), 1).per
    end

    test "it offsets by page" do
      page = Page.new(Product.order(:id), 2, per: 2)
      assert_equal Product.order(:id).offset(2).first(2).map(&:id), page.rows.map(&:id)
    end

    test "it clamps a page below one or past the end" do
      assert_equal 1, Page.new(Product.order(:id), "0", per: 2).number
      assert_equal 1, Page.new(Product.order(:id), nil, per: 2).number
      assert_equal 1, Page.new(Product.order(:id), "not a number", per: 2).number
      assert_equal Page.new(Product.order(:id), 1, per: 2).last,
                   Page.new(Product.order(:id), 9999, per: 2).number
    end

    test "an empty relation still reports one page" do
      page = Page.new(Product.where(id: nil), 3)

      assert page.empty?
      assert page.single?
      assert_equal 1, page.last
      assert_equal 1, page.number
      assert_empty page.rows
    end

    test "it reports the range it is showing" do
      page = Page.new(Product.order(:id), 2, per: 2)

      assert_equal 3, page.from
      assert_equal [ Product.count, 4 ].min, page.to
    end

    test "it counts past a custom select without tripping over the columns" do
      relation = ClientSearch.new({}).relation
      assert_equal User.where(admin: false).count, Page.new(relation, 1).total
    end

    test "an instance reports the window around the page it is on" do
      page = Page.new(Product.order(:id), 2, per: 2)
      assert_equal (1..page.last).to_a, page.window
    end

    test "seven pages or fewer are listed in full" do
      assert_equal (1..7).to_a, Page.window(1, 7)
      assert_equal [ 1 ], Page.window(1, 1)
    end

    test "a long list pads the head and elides the tail" do
      assert_equal [ 1, 2, 3, 4, :gap, 12 ], Page.window(1, 12)
      assert_equal [ 1, 2, 3, 4, :gap, 12 ], Page.window(3, 12)
    end

    test "a long list elides both sides in the middle" do
      assert_equal [ 1, :gap, 5, 6, 7, :gap, 12 ], Page.window(6, 12)
    end

    test "a long list pads the tail near the end" do
      assert_equal [ 1, :gap, 9, 10, 11, 12 ], Page.window(12, 12)
    end
  end
end
