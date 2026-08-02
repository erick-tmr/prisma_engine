require "test_helper"

class QuestionMailerTest < ActionMailer::TestCase
  def strike_for(user, question, count: 1)
    (count - 1).times do |index|
      QuestionStrike.create!(user: user, question: user.questions.create!(product: products(:yellow),
                                                                         body: "Pergunta anterior número #{index}."),
                             issued_by: users(:admin))
    end
    QuestionStrike.create!(user: user, question: question, issued_by: users(:admin))
  end

  test "answered quotes the question, the published reply and the protocol stamp" do
    question = questions(:answered_yellow)
    email = QuestionMailer.answered(question)

    assert_equal [ question.user.email ], email.to
    assert_equal [ "no-reply@prismagames.com.br" ], email.from
    assert_equal "Respondemos sua pergunta sobre #{question.product.name}", email.subject

    [ email.html_part, email.text_part ].each do |part|
      body = part.body.to_s

      assert_includes body, question.user.first_name
      assert_includes body, "Respondemos sua pergunta."
      assert_includes body, question.body
      assert_includes body, question.answer_body
      assert_includes body, question.product.name
      assert_includes body, "Sua pergunta"
      assert_includes body, I18n.l(question.created_at, format: :date_at_time)
      assert_includes body, "##{question.id}"
      assert_includes body, "Resposta da Prisma Games"
      assert_includes body, "Respondido pela equipe Prisma Games"
      assert_includes body, I18n.l(question.answered_at.to_date)
      assert_includes body, "Ver a resposta na loja"
      assert_includes body, "perguntas"
      assert_includes body, "este endereço não recebe respostas"
    end

    html_body = email.html_part.body.to_s

    assert_includes html_body, "#007bff"
    assert_includes html_body, "dragon-letter-full.png"
  end

  test "the first strike tells the customer the week-long pause and when it lifts" do
    strike = strike_for(users(:orderless), questions(:archived_yellow))
    email = QuestionMailer.strike(strike)

    assert_equal [ strike.user.email ], email.to
    assert_equal "Sua pergunta foi removida da loja", email.subject

    [ email.html_part, email.text_part ].each do |part|
      body = part.body.to_s

      assert_includes body, "1 semana sem poder perguntar"
      assert_includes body, I18n.l(1.week.from_now.to_date)
      assert_includes body, "Comprar continua liberado"
    end
  end

  test "the second strike raises the pause to a month" do
    strike = strike_for(users(:orderless), questions(:archived_yellow), count: 2)
    email = QuestionMailer.strike(strike)

    assert_includes email.text_part.body.to_s, "1 mês sem poder perguntar"
    assert_includes email.text_part.body.to_s, I18n.l(1.month.from_now.to_date)
  end

  test "the third strike states the block is now permanent and quotes no date" do
    strike = strike_for(users(:orderless), questions(:archived_yellow), count: 3)
    email = QuestionMailer.strike(strike)
    body = email.text_part.body.to_s

    assert_includes body, "não envia mais perguntas"
    assert_includes body, "terceira ocorrência"
    assert_not_includes body, I18n.l(Date.current)
  end
end
