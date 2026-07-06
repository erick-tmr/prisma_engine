module Users
  class ConfirmationsController < Devise::ConfirmationsController
    include EmailResendCooldown

    enforce_resend_cooldown flow: :confirmation, redirect_to: :new_user_confirmation_path

    def new
      super
      @email = params[:email].presence
      @resend_deadline = resend_deadline(:confirmation, @email)
    end

    def show
      super
      WelcomeMailer.account_created(resource).deliver_later if first_confirmation?
    end

    private

    def after_resending_confirmation_instructions_path_for(_resource_name)
      new_user_confirmation_path(email: resource.email)
    end

    def first_confirmation?
      resource.errors.empty? && resource.saved_change_to_confirmed_at.first.nil?
    end
  end
end
