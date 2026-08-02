require "test_helper"

module Questions
  class ModerateTest < ActiveSupport::TestCase
    include ActionMailer::TestHelper

    def moderate(question, event, answer_body: nil)
      Moderate.call(question: question, event: event, actor: users(:admin), answer_body: answer_body)
    end

    test "answering publishes the reply and stamps the moment" do
      question = questions(:awaiting_yellow)
      result = moderate(question, "answer", answer_body: "  Vem com caixa, sem manual.  ")

      assert_predicate result, :done?
      assert_predicate question.reload, :answered?
      assert_equal "Vem com caixa, sem manual.", question.answer_body
      assert_not_nil question.answered_at
    end

    test "answering with no text is refused so nothing is published" do
      question = questions(:awaiting_yellow)
      result = moderate(question, "answer", answer_body: "   ")

      assert_not_predicate result, :done?
      assert_equal "blank_answer", result.reason
      assert_predicate question.reload, :awaiting_answer?
    end

    test "saving a draft keeps the answer out of the storefront" do
      question = questions(:awaiting_yellow)
      result = moderate(question, "draft", answer_body: "Ainda confirmando com o fornecedor.")

      assert_predicate result, :done?
      assert_predicate question.reload, :draft?
      assert_nil question.answered_at
    end

    test "emptying a draft drops it back into the open queue" do
      question = questions(:draft_yellow)
      result = moderate(question, "draft", answer_body: "")

      assert_predicate result, :done?
      assert_predicate question.reload, :awaiting_answer?
      assert_nil question.answer_body
    end

    test "archiving takes the question off the storefront without a strike" do
      question = questions(:awaiting_yellow)

      assert_no_difference -> { QuestionStrike.count } do
        assert_predicate moderate(question, "archive"), :done?
      end
      assert_predicate question.reload, :archived?
    end

    test "marking spam hides the question and strikes the account" do
      question = questions(:awaiting_yellow)

      assert_difference -> { QuestionStrike.count }, 1 do
        assert_predicate moderate(question, "spam"), :done?
      end

      assert_predicate question.reload, :spam?
      assert_equal question.user, question.question_strike.user
      assert_equal users(:admin), question.question_strike.issued_by
    end

    test "marking spam twice does not stack a second strike" do
      result = moderate(questions(:spam_yellow), "spam")

      assert_not_predicate result, :done?
      assert_equal "already_spam", result.reason
    end

    test "releasing a spam question revokes the strike it caused" do
      question = questions(:spam_yellow)

      assert_difference -> { QuestionStrike.count }, -1 do
        assert_predicate moderate(question, "release"), :done?
      end

      assert_predicate question.reload, :awaiting_answer?
      assert_not_predicate Questions::Ban.new(question.user), :active?
    end

    test "releasing a question that already had an answer restores it as a draft" do
      question = questions(:archived_yellow)
      question.update_columns(answer_body: "Resposta que estava pronta.")

      assert_predicate moderate(question, "release"), :done?
      assert_predicate question.reload, :draft?
    end

    test "only moderated questions can be released" do
      result = moderate(questions(:awaiting_yellow), "release")

      assert_not_predicate result, :done?
      assert_equal "not_moderated", result.reason
    end

    test "an unknown event changes nothing" do
      question = questions(:awaiting_yellow)
      result = moderate(question, "explode")

      assert_not_predicate result, :done?
      assert_equal "unknown_event", result.reason
      assert_predicate question.reload, :awaiting_answer?
    end
  end
end
