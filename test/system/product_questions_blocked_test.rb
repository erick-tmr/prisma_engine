require "application_system_test_case"

class ProductQuestionsBlockedTest < ApplicationSystemTestCase
  def strike_customer(user, index: 0)
    question = user.questions.create!(product: products(:yellow), status: "spam",
                                      body: "Pergunta removida número #{index} da loja.")
    QuestionStrike.create!(user: user, question: question, issued_by: users(:admin))
  end

  def visit_yellow_questions
    visit product_path(slug: products(:yellow).slug)
    assert_selector "[data-question-form]"
  end

  def compose(body)
    fill_in "question[body]", with: body
    find("[data-question-submit]").click
  end

  test "a suspended customer gets the modal instead of sending the question" do
    strike_customer(users(:confirmed))
    login_as_user(users(:confirmed))

    visit_yellow_questions
    assert_no_selector "[data-question-blocked].is-open"

    assert_no_difference "Question.count" do
      compose "Esse cartucho funciona no Game Boy Advance SP?"
      assert_selector "[data-question-blocked].is-open"
    end

    assert_selector ".question-blocked__title", text: "Sua pergunta não foi enviada"
    assert_selector ".question-blocked__quote-text", text: "Pergunta removida número 0 da loja."
    assert_field "question[body]", with: "Esse cartucho funciona no Game Boy Advance SP?"
  end

  test "the modal closes on the dismiss button and reopens on the next attempt" do
    strike_customer(users(:confirmed))
    login_as_user(users(:confirmed))

    visit_yellow_questions
    compose "Esse cartucho funciona no Game Boy Advance SP?"
    assert_selector "[data-question-blocked].is-open"

    find("[data-question-blocked] .question-blocked__ok").click
    assert_no_selector "[data-question-blocked].is-open"

    find("[data-question-submit]").click
    assert_selector "[data-question-blocked].is-open"
  end

  test "a permanently blocked customer gets the final variant" do
    3.times { |index| strike_customer(users(:confirmed), index: index) }
    login_as_user(users(:confirmed))

    visit_yellow_questions
    compose "Esse cartucho funciona no Game Boy Advance SP?"

    assert_selector "[data-question-blocked].question-blocked--permanent.is-open"
    assert_selector ".question-blocked__title", text: "Perguntas bloqueadas nesta conta"
    assert_selector ".question-blocked__rule-value", text: "Permanente"
  end

  test "a customer in good standing sends the question with no modal in the way" do
    login_as_user(users(:confirmed))

    visit_yellow_questions

    assert_difference "Question.count", 1 do
      compose "Esse cartucho funciona no Game Boy Advance SP?"
      assert_text "Pergunta enviada"
    end

    assert_no_selector "[data-question-blocked]"
  end
end
