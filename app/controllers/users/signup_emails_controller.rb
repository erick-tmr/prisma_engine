module Users
  class SignupEmailsController < ApplicationController
    include PendingSignup

    rate_limit to: 5, within: 1.hour, with: :too_many_corrections, only: :update

    def update
      user = pending_signup_user
      return redirect_to new_user_confirmation_path unless user

      previous_email = user.email
      return if resume_pending_signup(user, params.expect(user: [ :email ])[:email])

      redirect_to new_user_confirmation_path(email: previous_email), alert: user.errors.full_messages.to_sentence
    end

    private

    def too_many_corrections
      redirect_to new_user_confirmation_path(email: pending_signup_user&.email), alert: t("auth.resend.ip_limit")
    end
  end
end
