require "test_helper"

module Admin
  class QuestionSearchTest < ActiveSupport::TestCase
    def search(params = {})
      QuestionSearch.new(ActionController::Parameters.new(params))
    end

    test "with no params the queue shows what is still owed an answer" do
      relation = search.relation

      assert_includes relation, questions(:awaiting_yellow)
      assert_not_includes relation, questions(:draft_yellow)
      assert_not_includes relation, questions(:answered_yellow)
    end

    test "each chip narrows to its own situation" do
      assert_includes search(status: "draft").relation, questions(:draft_yellow)
      assert_includes search(status: "answered").relation, questions(:answered_yellow)
      assert_includes search(status: "archived").relation, questions(:archived_yellow)
      assert_includes search(status: "spam").relation, questions(:spam_yellow)
    end

    test "the all chip drops the situation filter entirely" do
      relation = search(status: "all").relation

      assert_includes relation, questions(:awaiting_yellow)
      assert_includes relation, questions(:spam_yellow)
      assert_includes relation, questions(:answered_yellow)
    end

    test "the search matches the question body" do
      relation = search(status: "all", q: "caixa e manual").relation

      assert_includes relation, questions(:awaiting_yellow)
      assert_not_includes relation, questions(:answered_yellow)
    end

    test "the search matches the customer name and e-mail" do
      by_name = search(status: "all", q: "marina").relation
      by_email = search(status: "all", q: "comprador@example.com").relation

      assert_includes by_name, questions(:answered_yellow)
      assert_includes by_email, questions(:answered_yellow)
      assert_not_includes by_name, questions(:awaiting_yellow)
    end

    test "a like wildcard in the search is matched literally" do
      assert_empty search(status: "all", q: "%").relation
    end

    test "the product filter keeps one product's questions" do
      relation = search(status: "all", produto: products(:plastic_shell).id.to_s).relation

      assert_includes relation, questions(:answered_shell)
      assert_not_includes relation, questions(:answered_yellow)
    end

    test "the queue drains oldest first and can be flipped" do
      oldest = search(status: "all").relation.first
      newest = search(status: "all", sort: "newest").relation.first

      assert_equal questions(:archived_yellow), oldest
      assert_equal questions(:awaiting_yellow), newest
    end

    test "chip counts are reported for every situation" do
      counts = search.chip_counts

      assert_equal 1, counts["open"]
      assert_equal 1, counts["draft"]
      assert_equal 2, counts["answered"]
      assert_equal 1, counts["archived"]
      assert_equal 1, counts["spam"]
      assert_equal Question.count, counts["all"]
    end

    test "the product filter only offers products that were actually asked about" do
      assert_includes search.products, products(:yellow)
      assert_not_includes search.products, products(:metroid)
    end

    test "round-trip params leave the defaults out of the url" do
      assert_empty search.to_params
      assert_equal({ q: "caixa", status: "spam", produto: "7", sort: "newest" },
                   search(q: "caixa", status: "spam", produto: "7", sort: "newest").to_params)
    end

    test "hostile or nonsense params fall back to the defaults instead of raising" do
      hostile = search(status: "'; DROP TABLE questions; --", sort: "sideways", produto: "1 OR 1=1")

      assert_equal "open", hostile.chip
      assert_equal "oldest", hostile.sort
      assert_equal "", hostile.product
      assert_includes hostile.relation, questions(:awaiting_yellow)
    end
  end
end
