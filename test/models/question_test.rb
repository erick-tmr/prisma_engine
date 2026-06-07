require "test_helper"

class QuestionTest < ActiveSupport::TestCase
  test "requires body, asker name and a well-formed email" do
    question = Question.new(product: products(:yellow))
    assert_not question.valid?
    assert_includes question.errors.attribute_names, :body
    assert_includes question.errors.attribute_names, :asker_name

    question.asker_email = "not-an-email"
    question.valid?
    assert_includes question.errors[:asker_email], "não é válido"
  end

  test "published scope" do
    assert_includes Question.published, questions(:answered_published)
    assert_not_includes Question.published, questions(:unanswered)
  end

  test "answered_at is stamped the first time a question is answered" do
    question = questions(:unanswered)
    assert_nil question.answered_at
    question.update!(answered: true, answer_body: "Sim.")
    assert_not_nil question.answered_at
  end

  test "answered_at stays nil while a question remains unanswered" do
    question = Question.create!(
      product: products(:yellow),
      body: "Tem nota fiscal?",
      asker_name: "Maria",
      asker_email: "maria@example.com",
      answered: false
    )
    assert_nil question.answered_at
  end

  test "answered_at is preserved when an already-answered question is re-saved" do
    question = questions(:answered_published)
    original = question.answered_at
    question.update!(answer_body: "Sim, bateria nova inclusa (atualizado).")
    assert_equal original, question.reload.answered_at
  end
end
