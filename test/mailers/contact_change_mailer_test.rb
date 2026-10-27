require "test_helper"

class ContactChangeMailerTest < ActionMailer::TestCase
  test "previous_address tells the old inbox where the login moved" do
    user = users(:confirmed)
    user.email = "novo@example.com"
    email = ContactChangeMailer.previous_address(user, "antigo@example.com")

    assert_equal [ "antigo@example.com" ], email.to
    assert_equal [ "no-reply@prismagames.com.br" ], email.from
    assert_equal "Seu e-mail de acesso foi alterado", email.subject

    [ email.html_part, email.text_part ].each do |part|
      body = part.body.to_s
      assert_includes body, user.first_name
      assert_includes body, "novo@example.com"
      assert_includes body, "Não reconhece essa mudança?"
    end
  end

  test "new_address welcomes the new inbox as the login and links to sign in" do
    user = users(:confirmed)
    email = ContactChangeMailer.new_address(user)

    assert_equal [ user.email ], email.to
    assert_equal "Este é o novo e-mail da sua conta", email.subject

    [ email.html_part, email.text_part ].each do |part|
      body = part.body.to_s
      assert_includes body, user.first_name
      assert_includes body, "Entrar na minha conta"
      assert_includes body, "/entrar"
    end
  end
end
