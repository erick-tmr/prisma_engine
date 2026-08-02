require "test_helper"

class QuestionMailerTest < ActionMailer::TestCase
  def strike_for(user, question, count: 1)
    (count - 1).times do |index|
      QuestionStrike.create!(user: user, question: user.questions.create!(product: products(:yellow),
                                                                         body: "Pergunta anterior número #{index}."),
                             issued_by: users(:admin), created_at: (count - index).months.ago)
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

  test "the first strike quotes the removed question and the week-long pause" do
    question = questions(:archived_yellow)
    strike = strike_for(users(:orderless), question)
    email = QuestionMailer.strike(strike)

    assert_equal [ strike.user.email ], email.to
    assert_equal "Pergunta removida da loja", email.subject

    [ email.html_part, email.text_part ].each do |part|
      body = part.body.to_s

      assert_includes body, "Removemos sua pergunta da loja."
      assert_includes body, question.body
      assert_includes body, question.product.name
      assert_includes body, I18n.l(question.created_at, format: :date_at_time)
      assert_includes body, "##{question.id}"
      assert_includes body, "1 semana sem poder enviar perguntas."
      assert_includes body, I18n.l(1.week.from_now.to_date, format: :day_month_year)
      assert_includes body, "Ocorrência 1 de 3 · próxima: 1 mês sem perguntar"
      assert_includes body, "perguntas devem ser sobre o produto"
      assert_includes body, "Escrever para o suporte"
      assert_includes body, "Acha que foi engano?"
      assert_not_includes body, "Na próxima, o bloqueio é definitivo."
      assert_not_includes body, "Histórico desta conta"
    end

    html_body = email.html_part.body.to_s

    assert_includes html_body, "#e08a00"
    assert_includes html_body, "#fff8ec"
    assert_includes html_body, "dragon-fly.png"
  end

  test "the second strike raises the pause to a month and warns what comes next" do
    strike = strike_for(users(:orderless), questions(:archived_yellow), count: 2)
    email = QuestionMailer.strike(strike)

    assert_equal "Segunda pergunta removida da loja", email.subject

    [ email.html_part, email.text_part ].each do |part|
      body = part.body.to_s

      assert_includes body, "De novo: removemos sua pergunta."
      assert_includes body, "1 mês sem poder enviar perguntas."
      assert_includes body, I18n.l(1.month.from_now.to_date, format: :day_month_year)
      assert_includes body, I18n.l(2.months.ago.to_date)
      assert_includes body, "Ocorrência 2 de 3 · próxima: bloqueio definitivo"
      assert_includes body, "Na próxima, o bloqueio é definitivo."
      assert_not_includes body, "Histórico desta conta"
    end

    html_body = email.html_part.body.to_s

    assert_includes html_body, "Reincidência · 2ª ocorrência"
    assert_includes html_body, "#d64545"
    assert_includes html_body, "dragon-letter-full.png"
  end

  test "the third strike is permanent and lists every occurrence behind it" do
    strike = strike_for(users(:orderless), questions(:archived_yellow), count: 3)
    email = QuestionMailer.strike(strike)

    assert_equal "Bloqueio definitivo de perguntas", email.subject

    [ email.html_part, email.text_part ].each do |part|
      body = part.body.to_s

      assert_includes body, "Bloqueio permanente de perguntas."
      assert_includes body, "Histórico desta conta"
      assert_includes body, "1ª ocorrência · #{I18n.l(3.months.ago.to_date)}, 1 semana de bloqueio"
      assert_includes body, "2ª ocorrência · #{I18n.l(2.months.ago.to_date)}, 1 mês de bloqueio"
      assert_includes body, "3ª ocorrência · #{I18n.l(Date.current)}, bloqueio definitivo"
      assert_includes body, "Ocorrência 3 de 3 · limite atingido"
      assert_includes body, "revisar as três ocorrências"
      assert_not_includes body, "O bloqueio vale até"
      assert_not_includes body, "Na próxima, o bloqueio é definitivo."
    end

    html_body = email.html_part.body.to_s

    assert_includes html_body, "#b3261e"
    assert_includes html_body, "dragon-face.png"
  end
end
