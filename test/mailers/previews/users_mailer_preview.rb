class UsersMailerPreview < ActionMailer::Preview
  def confirmation_instructions
    Users::Mailer.confirmation_instructions(User.first, "preview-token")
  end

  def reset_password_instructions
    Users::Mailer.reset_password_instructions(User.first, "preview-token")
  end

  def unlock_instructions
    Users::Mailer.unlock_instructions(User.first, "preview-token")
  end

  def email_changed
    user = User.first
    user.unconfirmed_email = "novo-email@example.com"
    Users::Mailer.email_changed(user)
  end

  def password_change
    Users::Mailer.password_change(User.first)
  end
end
