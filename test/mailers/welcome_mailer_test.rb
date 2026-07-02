require "test_helper"

class WelcomeMailerTest < ActionMailer::TestCase
  test "account_created greets the customer and links to the store" do
    user = users(:confirmed)
    email = WelcomeMailer.account_created(user)

    assert_equal [ user.email ], email.to
    assert_equal [ "no-reply@prismagames.com.br" ], email.from
    assert_equal "Bem-vindo à Prisma Games!", email.subject

    [ email.html_part, email.text_part ].each do |part|
      body = part.body.to_s
      assert_includes body, user.first_name
      assert_includes body, "Explorar a loja"
    end

    assert_includes email.html_part.body.to_s, "dragon-face.png"
  end
end
