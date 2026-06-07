require "test_helper"

module Users
  class MailerTest < ActionMailer::TestCase
    test "Devise email is wrapped in our mailer layout with the help footer" do
      ActionMailer::Base.deliveries.clear
      users(:unconfirmed).send_confirmation_instructions

      email = ActionMailer::Base.deliveries.last
      assert_equal [ "no-reply@prismagames.com.br" ], email.from
      body = email.body.to_s
      assert_includes body, "Precisa de ajuda?"
      assert_includes body, "vininess@hotmail.com"
    end
  end
end
