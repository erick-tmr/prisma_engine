require "test_helper"

class CannedAnswerTest < ActiveSupport::TestCase
  def build_answer(overrides = {})
    CannedAnswer.new({ label: "Garantia", body: "Todos os cartuchos têm 90 dias de garantia." }.merge(overrides))
  end

  test "a shortcut needs a label" do
    answer = build_answer(label: " ")

    assert_not answer.valid?
    assert_includes answer.errors[:label], "não pode ficar em branco"
  end

  test "a label longer than the maximum is rejected" do
    answer = build_answer(label: "a" * 33)

    assert_not answer.valid?
    assert_includes answer.errors.attribute_names, :label
  end

  test "two shortcuts cannot share a label" do
    answer = build_answer(label: canned_answers(:compatibility).label)

    assert_not answer.valid?
    assert_includes answer.errors.attribute_names, :label
  end

  test "a body too short to stand on its own is rejected" do
    answer = build_answer(body: "Funciona.")

    assert_not answer.valid?
    assert_includes answer.errors.attribute_names, :body
  end

  test "a shortcut needs a body" do
    answer = build_answer(body: nil)

    assert_not answer.valid?
    assert_includes answer.errors[:body], "não pode ficar em branco"
  end

  test "surrounding whitespace is trimmed off both fields" do
    answer = build_answer(label: "  Garantia  ", body: "  Todos os cartuchos têm garantia.  ")
    answer.validate

    assert_equal "Garantia", answer.label
    assert_equal "Todos os cartuchos têm garantia.", answer.body
  end

  test "shortcuts read in the order they were created" do
    assert_equal [ canned_answers(:compatibility), canned_answers(:production_time) ], CannedAnswer.ordered.to_a
  end
end
