require "test_helper"

module Users
  class ConfirmationsControllerTest < ActionDispatch::IntegrationTest
    include ActionMailer::TestHelper

    test "confirming for the first time enqueues the welcome email" do
      user = users(:unconfirmed)

      assert_enqueued_email_with WelcomeMailer, :account_created, args: [ user ] do
        get user_confirmation_path(confirmation_token: "raw-token-pendente")
      end

      assert user.reload.confirmed_at.present?
    end

    test "reconfirming a changed email does not enqueue the welcome email" do
      user = users(:confirmed)
      ActionMailer::Base.deliveries.clear
      user.update!(email: "novo-email@example.com")

      reconfirmation_mail = ActionMailer::Base.deliveries.find { |mail| mail.to.include?("novo-email@example.com") }
      raw_token = reconfirmation_mail.html_part.body.to_s[/confirmation_token=([^"&]+)/, 1]

      assert_no_enqueued_emails do
        get user_confirmation_path(confirmation_token: raw_token)
      end

      assert_equal "novo-email@example.com", user.reload.email
      assert_nil user.unconfirmed_email
    end

    test "an invalid confirmation token does not enqueue the welcome email" do
      assert_no_enqueued_emails do
        get user_confirmation_path(confirmation_token: "no-such-token")
      end
    end
  end
end
