require "test_helper"

class QuestionTest < ActiveSupport::TestCase
  def build_question(overrides = {})
    Question.new({
      product: products(:yellow),
      user: users(:confirmed),
      body: "Esse cartucho funciona no Game Boy Advance?"
    }.merge(overrides))
  end

  test "a question without a body is rejected" do
    question = build_question(body: nil)

    assert_not question.valid?
    assert_includes question.errors[:body], "não pode ficar em branco"
  end

  test "a body shorter than the minimum is rejected" do
    question = build_question(body: "Funciona?")

    assert_not question.valid?
    assert_includes question.errors[:body], "precisa ter pelo menos 10 caracteres"
  end

  test "a body longer than the maximum is rejected" do
    question = build_question(body: "a" * 501)

    assert_not question.valid?
    assert_includes question.errors[:body], "pode ter no máximo 500 caracteres"
  end

  test "the body is stripped before validation" do
    question = build_question(body: "  Vem com caixa rígida?  ")
    question.validate

    assert_equal "Vem com caixa rígida?", question.body
  end

  test "a question needs an asker" do
    question = build_question(user: nil)

    assert_not question.valid?
    assert_includes question.errors.attribute_names, :user
  end

  test "a new question starts awaiting an answer" do
    assert_predicate build_question, :awaiting_answer?
  end

  test "a status outside the known set is rejected" do
    question = build_question(status: "publicada")

    assert_not question.valid?
    assert_includes question.errors.attribute_names, :status
  end

  test "an answered question needs answer text" do
    question = build_question(status: "answered")

    assert_not question.valid?
    assert_includes question.errors.attribute_names, :answer_body
  end

  test "a question awaiting an answer needs no answer text" do
    assert_predicate build_question(status: "awaiting_answer"), :valid?
  end

  test "visible questions leave out the moderated ones" do
    visible = Question.visible

    assert_includes visible, questions(:answered_yellow)
    assert_includes visible, questions(:awaiting_yellow)
    assert_not_includes visible, questions(:spam_yellow)
    assert_not_includes visible, questions(:archived_yellow)
  end

  test "newest first puts the most recent question on top" do
    ordered = Question.where(product: products(:yellow)).newest_first

    assert_equal questions(:awaiting_yellow), ordered.first
    assert_equal questions(:archived_yellow), ordered.last
  end

  test "answered_at is stamped the first time a question is answered" do
    question = questions(:awaiting_yellow)

    assert_nil question.answered_at
    question.update!(status: "answered", answer_body: "Vem com caixa, sem manual.")

    assert_not_nil question.answered_at
  end

  test "answered_at stays nil while the question waits" do
    question = questions(:awaiting_yellow)
    question.update!(body: "Vem com caixa, manual e encarte?")

    assert_nil question.answered_at
  end

  test "answered_at is preserved when an answered question is edited" do
    question = questions(:answered_yellow)
    stamped = question.answered_at
    question.update!(answer_body: "Salva sim, o save é em FRAM.")

    assert_equal stamped, question.reload.answered_at
  end
end
