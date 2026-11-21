module PendingSignup
  extend ActiveSupport::Concern
  include EmailResendCooldown

  SESSION_KEY = :signup_user_id

  private

  def remember_pending_signup(user)
    session[SESSION_KEY] = user.id
  end

  def pending_signup_user
    User.clients.find_by(id: session[SESSION_KEY], confirmed_at: nil)
  end

  def resume_pending_signup(user, email)
    previous_email = user.email
    return false unless user.correct_signup_email(email)

    remember_pending_signup(user)
    announce_corrected_email(user) unless user.email == previous_email
    redirect_to new_user_confirmation_path(email: user.email)
    true
  end

  def announce_corrected_email(user)
    record_resend_cooldown(:confirmation, user.email)
    flash[:notice] = t("auth.confirmations.email_corrected", email: user.email)
  end
end
