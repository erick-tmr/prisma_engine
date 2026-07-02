require "test_helper"

module Users
  class MailerTest < ActionMailer::TestCase
    test "confirmation instructions carry the redesigned copy and a working link" do
      ActionMailer::Base.deliveries.clear
      user = users(:unconfirmed)
      user.send_confirmation_instructions

      email = ActionMailer::Base.deliveries.last
      html_body = email.html_part.body.to_s
      text_body = email.text_part.body.to_s

      assert_equal [ "no-reply@prismagames.com.br" ], email.from
      assert_includes html_body, "Falta só um passo: confirme seu e-mail."
      assert_includes html_body, "Confirmar meu e-mail"
      assert_includes html_body, "Precisa de ajuda?"
      assert_includes html_body, "vininess@hotmail.com"

      raw_token = html_body[/confirmation_token=([^"&]+)/, 1]
      assert_includes text_body, raw_token
    end

    test "reset password instructions carry the redesigned copy and a working link" do
      ActionMailer::Base.deliveries.clear
      user = users(:confirmed)
      raw_token = user.send_reset_password_instructions

      email = ActionMailer::Base.deliveries.last
      html_body = email.html_part.body.to_s
      text_body = email.text_part.body.to_s

      assert_includes html_body, "Vamos redefinir sua senha."
      assert_includes html_body, "Criar nova senha"
      assert_includes html_body, "6 horas"
      assert_includes html_body, raw_token
      assert_includes text_body, raw_token
    end

    test "unlock instructions carry the redesigned copy and a working link" do
      ActionMailer::Base.deliveries.clear
      user = users(:locked)
      raw_token = user.send_unlock_instructions

      email = ActionMailer::Base.deliveries.last
      html_body = email.html_part.body.to_s
      text_body = email.text_part.body.to_s

      assert_includes html_body, "Bloqueamos sua conta por segurança."
      assert_includes html_body, "Desbloquear minha conta"
      assert_includes html_body, raw_token
      assert_includes text_body, raw_token
    end

    test "email changed notification shows the new pending address" do
      user = users(:confirmed)
      ActionMailer::Base.deliveries.clear
      user.update!(email: "novo-email@example.com")

      email = ActionMailer::Base.deliveries.find { |mail| mail.to.include?(user.email) }
      html_body = email.html_part.body.to_s
      text_body = email.text_part.body.to_s

      assert_includes html_body, "Seu e-mail de acesso foi alterado."
      assert_includes html_body, "novo-email@example.com"
      assert_includes text_body, "novo-email@example.com"
    end

    test "password change notification fires after a password update" do
      user = users(:confirmed)
      ActionMailer::Base.deliveries.clear
      user.update!(password: "novaSenha123", password_confirmation: "novaSenha123")

      email = ActionMailer::Base.deliveries.last
      html_body = email.html_part.body.to_s
      text_body = email.text_part.body.to_s

      assert_includes html_body, "Sua senha foi alterada com sucesso."
      assert_includes text_body, "Sua senha foi alterada com sucesso."
    end
  end
end
