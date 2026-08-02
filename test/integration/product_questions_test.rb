require "test_helper"

class ProductQuestionsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    ActionController::Base.cache_store.clear
  end

  def yellow_path
    product_path(slug: products(:yellow).slug)
  end

  def ask(body, product: products(:yellow))
    post product_questions_path(slug: product.slug), params: { question: { body: body } }
  end

  def strike_customer(user, index: 0)
    question = user.questions.create!(product: products(:yellow), status: "spam",
                                      body: "Pergunta removida número #{index} da loja.")
    QuestionStrike.create!(user: user, question: question, issued_by: users(:admin))
  end

  test "the section renders the heading, the lede and both stat pills" do
    get yellow_path

    assert_response :success
    assert_select "section.product-questions#perguntas"
    assert_select ".product-questions__title", text: "Perguntas e respostas"
    assert_match(/quem responde é a equipe que monta os cartuchos/, response.body)
    assert_select ".product-questions__stat--answered b", text: "1"
    assert_select ".product-questions__stat--awaiting b", text: "2"
  end

  test "the awaiting pill is left out when every question has an answer" do
    get product_path(slug: products(:plastic_shell).slug)

    assert_response :success
    assert_select ".product-questions__stat--answered b", text: "1"
    assert_select ".product-questions__stat--awaiting", false
  end

  test "questions marked as spam or archived stay off the storefront" do
    get yellow_path

    assert_response :success
    assert_no_match(/ganhe dinheiro rápido/, response.body)
    assert_no_match(/já não faz sentido no catálogo atual/, response.body)
    assert_select "[data-question-item]", count: 3
  end

  test "a question whose answer is still a draft shows the question but never the draft" do
    get yellow_path

    assert_response :success
    assert_match(/Dá para escolher a cor da carcaça/, response.body)
    assert_no_match(/é só combinar as duas opções/, response.body)
  end

  test "an answered question renders the Prisma answer under it" do
    get yellow_path

    assert_response :success
    assert_select "[data-question-answer] .product-questions__author", text: "Prisma Games"
    assert_select "[data-question-answer] .product-questions__team", text: "Equipe"
    assert_select "[data-question-answer] .product-questions__text",
                  text: "Salva sim, o save é em FRAM e não depende de bateria."
  end

  test "a question still waiting renders the waiting pill instead of an answer" do
    get yellow_path

    assert_response :success
    assert_select "[data-question-waiting]", count: 2
    assert_select "[data-question-waiting]", text: /Aguardando resposta da Prisma/
  end

  test "each question carries a machine timestamp and a relative label" do
    get yellow_path

    assert_response :success
    assert_select "time.product-questions__time[datetime]"
    assert_select "time.product-questions__time", text: /\Ahá \d+ dias?\z/
  end

  test "a visitor sees the sign-in gate instead of the composer" do
    get yellow_path

    assert_response :success
    assert_select "[data-question-gate]"
    assert_select "[data-question-gate] a[href=?]", new_user_session_path
    assert_select "[data-question-gate] a[href=?]", new_user_registration_path
    assert_select "[data-question-form]", false
  end

  test "a signed-in customer sees the composer addressed to them" do
    sign_in users(:confirmed)

    get yellow_path

    assert_response :success
    assert_select "[data-question-form]"
    assert_select ".product-questions__who-name", text: users(:confirmed).full_name
    assert_select "textarea[data-question-body][maxlength=?][data-min-length=?]", "500", "10"
    assert_select "[data-question-gate]", false
  end

  test "the submit button ships enabled so the form still works without JavaScript" do
    sign_in users(:confirmed)

    get yellow_path

    assert_response :success
    assert_select "[data-question-submit]"
    assert_select "[data-question-submit][disabled]", false
  end

  test "the foot ships the full list and hides the reveal button for JavaScript to claim" do
    get yellow_path

    assert_response :success
    assert_select "[data-question-count][data-template=?]", "Mostrando {n} de 3 perguntas"
    assert_select ".product-questions__count", text: "Mostrando 3 de 3 perguntas"
    assert_select "[data-question-more][hidden]"
  end

  test "a product nobody has asked about shows the empty state" do
    get product_path(slug: products(:metroid).slug)

    assert_response :success
    assert_select "section.product-questions.is-empty"
    assert_select ".product-questions__empty-title", text: "Seja o primeiro a perguntar"
    assert_select "[data-question-list]", false
    assert_select "[data-question-more]", false
  end

  test "a customer in good standing never gets the blocked modal" do
    sign_in users(:confirmed)

    get yellow_path

    assert_response :success
    assert_select "[data-question-blocked]", false
  end

  test "a visitor never gets the blocked modal" do
    get yellow_path

    assert_response :success
    assert_select "[data-question-blocked]", false
  end

  test "a customer whose suspension has lifted no longer gets the blocked modal" do
    strike_customer(users(:confirmed)).update!(created_at: 8.days.ago)
    sign_in users(:confirmed)

    get yellow_path

    assert_response :success
    assert_select "[data-question-blocked]", false
  end

  test "the blocked modal quotes the removed question and offers the support handoff" do
    strike_customer(users(:confirmed))
    sign_in users(:confirmed)

    get yellow_path

    assert_response :success
    assert_select "[data-question-blocked] .question-blocked__quote-meta b", text: "Pokemon Yellow Version"
    assert_select "[data-question-blocked] .question-blocked__quote-text",
                  text: "Pergunta removida número 0 da loja."
    assert_select "[data-question-blocked] .question-blocked__removed", text: /Removida/
    assert_select "[data-question-blocked] a.question-blocked__support[href=?]", "https://wa.me/5535920001100"
    assert_select "[data-question-blocked] .question-blocked__fine",
                  text: /continua salva no campo/
  end

  test "a first strike blocks with the seven day copy and the date questions reopen" do
    travel_to Time.zone.local(2026, 8, 2, 14, 30) do
      strike_customer(users(:confirmed))
      sign_in users(:confirmed)

      get yellow_path

      assert_response :success
      assert_select ".question-blocked.question-blocked--permanent", false
      assert_select ".question-blocked__bubble", text: /Pare aí mesmo\./
      assert_select ".question-blocked__title", text: "Sua pergunta não foi enviada"
      assert_select ".question-blocked__lead", text: /pausadas por 7 dias/
      assert_select ".question-blocked__rule-label", text: "Volta a perguntar em"
      assert_select ".question-blocked__rule-value", text: /9 de agosto, 14h30/
      assert_select ".question-blocked__rule-value i.bi-clock-history"
    end
  end

  test "a second strike blocks for a month and warns the next one is permanent" do
    travel_to Time.zone.local(2026, 8, 2, 14, 30) do
      2.times { |index| strike_customer(users(:confirmed), index: index) }
      sign_in users(:confirmed)

      get yellow_path

      assert_response :success
      assert_select ".question-blocked.question-blocked--permanent", false
      assert_select ".question-blocked__title", text: "Sua pergunta não foi enviada"
      assert_select ".question-blocked__lead", text: /a pausa agora é de 1 mês/
      assert_select ".question-blocked__lead", text: /o bloqueio passa a ser permanente/
      assert_select ".question-blocked__rule-value", text: /2 de setembro, 14h30/
    end
  end

  test "a third strike blocks for good and drops the countdown" do
    3.times { |index| strike_customer(users(:confirmed), index: index) }
    sign_in users(:confirmed)

    get yellow_path

    assert_response :success
    assert_select ".question-blocked.question-blocked--permanent"
    assert_select ".question-blocked__bubble", text: /Acesso negado\./
    assert_select ".question-blocked__title", text: "Perguntas bloqueadas nesta conta"
    assert_select ".question-blocked__lead", text: /o bloqueio de perguntas agora é permanente/
    assert_select ".question-blocked__rule-label", text: "Duração do bloqueio"
    assert_select ".question-blocked__rule-value", text: /Permanente/
    assert_select ".question-blocked__rule-value i.bi-slash-circle"
    assert_select ".question-blocked__rule-value i.bi-clock-history", false
  end

  test "the blocked modal ships the stylesheet and the script that opens it" do
    strike_customer(users(:confirmed))
    sign_in users(:confirmed)

    get yellow_path

    assert_response :success
    assert_select "link[rel=stylesheet][href*=?]", "components/question-blocked"
    assert_select "script[type=module][src*=?]", "storefront/question_blocked"
  end

  test "a signed-in customer can ask a question" do
    sign_in users(:confirmed)

    assert_difference "Question.count", 1 do
      ask "Esse cartucho funciona no Game Boy Advance SP?"
    end

    question = Question.order(:created_at).last
    assert_equal users(:confirmed), question.user
    assert_equal products(:yellow), question.product
    assert_predicate question, :awaiting_answer?
    assert_redirected_to "#{yellow_path}#perguntas"
    assert_equal "Pergunta enviada. Avisamos por e-mail assim que a Prisma responder.", flash[:success]
  end

  test "the submitted body is stripped" do
    sign_in users(:confirmed)
    ask "   Vem com caixa rígida e manual?   "

    assert_equal "Vem com caixa rígida e manual?", Question.order(:created_at).last.body
  end

  test "a visitor is sent to sign in and brought back to the questions" do
    assert_no_difference "Question.count" do
      ask "Esse cartucho funciona no Game Boy Advance SP?"
    end

    assert_redirected_to new_user_session_path
    assert_equal "Entre na sua conta para perguntar sobre este produto.", flash[:notice]
    assert_equal "#{yellow_path}#perguntas", session["user_return_to"]
  end

  test "a question shorter than the minimum is rejected with a readable message" do
    sign_in users(:confirmed)

    assert_no_difference "Question.count" do
      ask "Funciona?"
    end

    assert_redirected_to "#{yellow_path}#perguntas"
    assert_equal "Pergunta precisa ter pelo menos 10 caracteres", flash[:error]
  end

  test "questions cannot be asked about a draft product" do
    sign_in users(:confirmed)

    assert_no_difference "Question.count" do
      ask "Esse cartucho funciona no Game Boy Advance SP?", product: products(:staged)
    end

    assert_response :not_found
  end

  test "questions cannot be asked about an unknown product" do
    sign_in users(:confirmed)

    post product_questions_path(slug: "nao-existe"), params: { question: { body: "Tem esse jogo?" } }

    assert_response :not_found
  end

  test "a customer serving a spam suspension cannot ask again until it lifts" do
    strike_customer(users(:confirmed))
    sign_in users(:confirmed)

    assert_no_difference "Question.count" do
      ask "Esse cartucho funciona no Game Boy Advance SP?"
    end

    assert_redirected_to "#{yellow_path}#perguntas"
    assert_equal "Uma pergunta sua foi marcada como spam, então sua conta só volta a perguntar em " \
                 "#{I18n.l(1.week.from_now.to_date)}.", flash[:alert]
  end

  test "a customer struck three times is done asking for good" do
    3.times { |index| strike_customer(users(:confirmed), index: index) }
    sign_in users(:confirmed)

    assert_no_difference "Question.count" do
      ask "Esse cartucho funciona no Game Boy Advance SP?"
    end

    assert_equal "Sua conta não pode mais enviar perguntas. Se acha que houve engano, fale com o suporte.",
                 flash[:alert]
  end

  test "a customer whose suspension has expired can ask again" do
    strike_customer(users(:confirmed)).update!(created_at: 8.days.ago)
    sign_in users(:confirmed)

    assert_difference "Question.count", 1 do
      ask "Esse cartucho funciona no Game Boy Advance SP?"
    end
  end

  test "a customer firing off questions is throttled" do
    sign_in users(:confirmed)

    assert_difference "Question.count", 5 do
      5.times { |index| ask "Pergunta número #{index} sobre este cartucho?" }
    end

    assert_no_difference "Question.count" do
      ask "Mais uma pergunta sobre este cartucho?"
    end

    assert_redirected_to "#{yellow_path}#perguntas"
    assert_equal "Você já enviou várias perguntas agora há pouco. Tente de novo mais tarde.", flash[:alert]
  end
end
