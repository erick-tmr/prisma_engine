module Users
  class PasswordsController < Devise::PasswordsController
    include EmailResendCooldown

    enforce_resend_cooldown flow: :password, redirect_to: :new_user_password_path

    def new
      super
      @email = params[:email].presence
      @resend_deadline = resend_deadline(:password, @email)
    end

    private

    def after_sending_reset_password_instructions_path_for(_resource_name)
      new_user_password_path(email: resource.email)
    end
  end
end
