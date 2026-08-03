require "test_helper"

module Admin
  class QuestionsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers
    include ActionMailer::TestHelper

    test "signed-out visitors are sent to the backoffice login" do
      get admin_questions_path

      assert_redirected_to admin_login_path
    end

    test "signed-in non-admins are sent to the backoffice login" do
      sign_in users(:confirmed)
      get admin_questions_path

      assert_redirected_to admin_login_path
    end

    test "the inbox opens on the answer queue and counts every situation" do
      sign_in users(:admin)
      get admin_questions_path

      assert_response :success
      assert_select ".app[data-list=?]", "questions"
      assert_select ".chip.on", text: /Abertas/
      assert_select "tr[data-question=?]", questions(:awaiting_yellow).id.to_s
      assert_select "tr[data-question=?]", questions(:answered_yellow).id.to_s, count: 0
      assert_select "#questions-count", text: "1 pergunta"
    end

    test "the sidebar advertises how many questions are still unanswered" do
      sign_in users(:admin)
      get admin_questions_path

      assert_select ".sb-link[href=?] .count", admin_questions_path, text: Question.awaiting_answer.count.to_s
    end

    test "a chip narrows the list and keeps the filter in the url" do
      sign_in users(:admin)
      get admin_questions_path, params: { status: "spam" }

      assert_response :success
      assert_select "tr[data-question=?]", questions(:spam_yellow).id.to_s
      assert_select "tr[data-question=?]", questions(:awaiting_yellow).id.to_s, count: 0
      assert_select "[data-bulk=?]", "release"
    end

    test "the release bulk action is offered only while reviewing spam" do
      sign_in users(:admin)
      get admin_questions_path

      assert_select "[data-bulk=?][hidden]", "release"
    end

    test "a fetch request returns just the results, without the page shell" do
      sign_in users(:admin)
      get admin_questions_path, headers: { "X-Requested-With" => "fetch" }

      assert_response :success
      assert_no_match(/<html/, response.body)
      assert_select "[data-part=chips]", count: 1
      assert_select "[data-part=count]", count: 1
      assert_select "[data-part=table]", count: 1
      assert_select "[data-part=drawer]", count: 1
      assert_select ".sidebar", count: 0
    end

    test "the drawer stays empty until a question is named in the url" do
      sign_in users(:admin)
      get admin_questions_path

      assert_select "[data-part=drawer] .dw-head", count: 0
    end

    test "naming a question in the url opens its answer composer" do
      question = questions(:awaiting_yellow)
      sign_in users(:admin)
      get admin_questions_path, params: { pergunta: question.id }

      assert_response :success
      assert_select "[data-part=drawer] .dw-q p", text: question.body
      assert_select "#dw-answer"
      assert_select "[data-canned-body]", count: CannedAnswer.count
      assert_select "button[name=event][value=?]", "answer"
      assert_select "[data-part=spam] #spam-modal"
    end

    test "an already answered question opens with its reply loaded" do
      question = questions(:answered_yellow)
      sign_in users(:admin)
      get admin_questions_path, params: { status: "answered", pergunta: question.id }

      assert_response :success
      assert_select "#dw-answer", text: question.answer_body
      assert_select "button[name=event][value=?]", "answer", text: /Atualizar resposta/
    end

    test "a spam question offers a release instead of another strike" do
      sign_in users(:admin)
      get admin_questions_path, params: { status: "spam", pergunta: questions(:spam_yellow).id }

      assert_response :success
      assert_select "button[name=event][value=?]", "release"
      assert_select "[data-spam-open]", count: 0
      assert_select "[data-part=spam] #spam-modal", count: 0
    end

    test "a spam question offers no way to answer it, only to release it" do
      sign_in users(:admin)
      get admin_questions_path, params: { status: "spam", pergunta: questions(:spam_yellow).id }

      assert_response :success
      assert_select "button[name=event][value=?]", "draft", count: 0
      assert_select "button[name=event][value=?]", "answer", count: 0
      assert_select "#dw-answer", count: 0
      assert_select ".dw-locked"
    end

    test "answering a spam question is refused instead of stranding its strike" do
      sign_in users(:admin)
      question = questions(:spam_yellow)

      assert_no_difference -> { QuestionStrike.count } do
        patch admin_question_path(question), params: { event: "answer", answer_body: "Vem com caixa." }
      end

      assert_equal I18n.t("admin.questions.errors.spam_locked"), flash[:alert]
      assert_nil flash[:notice]
      assert_predicate question.reload, :spam?
    end

    test "the spam confirmation spells out the penalty the account is about to take" do
      sign_in users(:admin)
      get admin_questions_path, params: { pergunta: questions(:awaiting_yellow).id }

      assert_response :success
      assert_select "#spam-modal .mdl-penalty b", text: /1 semana sem perguntar/
    end

    test "a repeat offender's history is shown before the operator confirms" do
      sign_in users(:admin)
      get admin_questions_path, params: { status: "all", pergunta: questions(:answered_yellow).id }

      assert_response :success
      assert_select "#spam-modal .rep", text: "1ª ocorrência"
      assert_select "#spam-modal .mdl-penalty b", text: /1 m[êe]s sem perguntar/
    end

    test "an unknown question in the url is ignored instead of blowing up" do
      sign_in users(:admin)
      get admin_questions_path, params: { pergunta: "0" }

      assert_response :success
      assert_select "[data-part=drawer] .dw-head", count: 0
    end

    test "answering publishes the reply, emails the customer and returns to the filtered list" do
      question = questions(:awaiting_yellow)
      sign_in users(:admin)

      assert_enqueued_email_with QuestionMailer, :answered, args: [ question ] do
        patch admin_question_path(question), params: { event: "answer", answer_body: "Vem com caixa, sem manual.", status: "all", q: "caixa" }
      end

      assert_redirected_to admin_questions_path(q: "caixa", status: "all")
      assert_predicate question.reload, :answered?
      assert_equal "Resposta publicada e enviada para o cliente.", flash[:notice]
    end

    test "sending an empty answer is refused with a reason" do
      question = questions(:awaiting_yellow)
      sign_in users(:admin)
      patch admin_question_path(question), params: { event: "answer", answer_body: "  " }

      assert_redirected_to admin_questions_path
      assert_equal "Escreva a resposta antes de enviar.", flash[:alert]
      assert_predicate question.reload, :awaiting_answer?
    end

    test "saving a draft keeps the answer private" do
      question = questions(:awaiting_yellow)
      sign_in users(:admin)

      assert_no_enqueued_emails do
        patch admin_question_path(question), params: { event: "draft", answer_body: "Ainda confirmando." }
      end

      assert_predicate question.reload, :draft?
    end

    test "marking spam strikes the account and warns it by e-mail" do
      question = questions(:awaiting_yellow)
      sign_in users(:admin)

      assert_difference -> { QuestionStrike.count }, 1 do
        assert_enqueued_emails 1 do
          patch admin_question_path(question), params: { event: "spam" }
        end
      end

      assert_predicate question.reload, :spam?
      assert_equal users(:admin), question.question_strike.issued_by
    end

    test "releasing a spam question clears the strike behind it" do
      question = questions(:spam_yellow)
      sign_in users(:admin)

      assert_difference -> { QuestionStrike.count }, -1 do
        patch admin_question_path(question), params: { event: "release" }
      end

      assert_predicate question.reload, :awaiting_answer?
    end

    test "an unknown event is refused instead of applied" do
      question = questions(:awaiting_yellow)
      sign_in users(:admin)
      patch admin_question_path(question), params: { event: "explode" }

      assert_redirected_to admin_questions_path
      assert_equal "Ação desconhecida.", flash[:alert]
      assert_predicate question.reload, :awaiting_answer?
    end

    test "hostile or nonsense params fall back to the defaults instead of raising" do
      sign_in users(:admin)
      get admin_questions_path, params: { page: "0", status: "not_a_status", sort: "sideways",
                                          produto: "1; DROP TABLE questions", pergunta: "abc" }

      assert_response :success
      assert_select "[data-part=table]"

      get admin_questions_path, params: { page: "99999" }

      assert_response :success
    end
  end
end
