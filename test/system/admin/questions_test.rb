require "application_system_test_case"

class AdminQuestionsTest < ApplicationSystemTestCase
  setup { login_as_user(users(:admin)) }

  test "an operator answers a question with a canned reply and it leaves the queue" do
    question = questions(:awaiting_yellow)
    visit admin_questions_path

    assert_selector ".chip.on", text: "Abertas"
    assert_selector "#questions-count", text: "1 pergunta"

    find("tr[data-question='#{question.id}']").click

    assert_current_path(/pergunta=#{question.id}/)
    assert_selector "#drawer.open"
    assert_selector ".dw-q p", text: question.body

    find("[data-canned-body]", match: :first).click
    assert_selector "[data-answer-counter]", text: /\d+ caracteres/

    click_button "Enviar resposta"

    assert_selector ".toast", text: "Resposta publicada"
    assert_selector "#questions-count", text: "0 perguntas"
    assert_no_selector "#drawer.open"
    assert_predicate question.reload, :answered?
    assert_equal canned_answers(:compatibility).body, question.answer_body
  end

  test "an operator saves a draft and finds it again under Rascunhos" do
    question = questions(:awaiting_yellow)
    visit admin_questions_path(pergunta: question.id)

    fill_in "dw-answer", with: "Ainda confirmando com o fornecedor."
    click_button "Salvar rascunho"

    assert_selector ".toast", text: "Rascunho salvo"

    find(".chip", text: "Rascunhos").click

    assert_current_path(/status=draft/)
    assert_selector "tr[data-question='#{question.id}']"
    assert_predicate question.reload, :draft?
  end

  test "an operator confirms the penalty before marking a question as spam" do
    question = questions(:awaiting_yellow)
    visit admin_questions_path(pergunta: question.id)

    click_button "Spam"

    assert_selector "#spam-modal.open"
    assert_selector ".mdl-penalty", text: "1 semana sem perguntar"

    click_button "Cancelar"
    assert_no_selector "#spam-modal.open"
    assert_predicate question.reload, :awaiting_answer?

    click_button "Spam"
    within "#spam-modal" do
      click_button "Marcar como spam"
    end

    assert_selector ".toast", text: "marcada como spam"
    assert_predicate question.reload, :spam?
    assert_equal users(:admin), question.question_strike.issued_by
  end

  test "an operator releases a question and the strike goes with it" do
    question = questions(:spam_yellow)
    visit admin_questions_path(status: "spam", pergunta: question.id)

    assert_selector ".pill", text: "Spam"

    assert_difference -> { QuestionStrike.count }, -1 do
      click_button "Não é spam"
      assert_selector ".toast", text: "liberada"
    end

    assert_predicate question.reload, :awaiting_answer?
  end

  test "an operator archives a selection from the bulk bar" do
    visit admin_questions_path(status: "all")

    assert_selector "#bulkbar[hidden]", visible: :all
    find("tr[data-question='#{questions(:awaiting_yellow).id}'] [data-check]").click
    find("tr[data-question='#{questions(:draft_yellow).id}'] [data-check]").click

    assert_selector "#bulk-n", text: "2"
    click_button "Arquivar"

    assert_selector ".toast", text: "2 perguntas arquivadas"
    assert_predicate questions(:awaiting_yellow).reload, :archived?
    assert_predicate questions(:draft_yellow).reload, :archived?
  end

  test "an operator adds a canned reply and it shows up in the composer" do
    visit admin_questions_path(pergunta: questions(:awaiting_yellow).id)

    assert_selector "[data-canned-body]", count: 2
    find(".dw-label [data-canned-open]").click

    assert_selector "#canned-modal.open"
    fill_in "canned-label", with: "Nota fiscal"
    fill_in "canned-body", with: "Emitimos nota fiscal para pessoa física e jurídica em todos os pedidos."
    click_button "Adicionar"

    assert_selector ".toast", text: "Atalho Nota fiscal criado"
    assert_selector "#canned-modal.open"
    assert_selector ".cn-row", text: "Nota fiscal"
  end
end
