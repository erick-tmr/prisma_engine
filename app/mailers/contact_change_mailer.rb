class ContactChangeMailer < ApplicationMailer
  def previous_address(user, previous_email)
    @user = user
    mail(to: previous_email, subject: default_i18n_subject)
  end

  def new_address(user)
    @user = user
    mail(to: user.email, subject: default_i18n_subject)
  end
end
