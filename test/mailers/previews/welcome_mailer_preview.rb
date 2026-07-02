class WelcomeMailerPreview < ActionMailer::Preview
  def account_created
    WelcomeMailer.account_created(User.first)
  end
end
