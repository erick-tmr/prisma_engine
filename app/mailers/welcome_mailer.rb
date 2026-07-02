class WelcomeMailer < ApplicationMailer
  def account_created(user)
    @user = user
    mail(to: user.email, subject: default_i18n_subject)
  end
end
