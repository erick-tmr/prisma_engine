module Users
  class UnlocksController < Devise::UnlocksController
    include EmailResendCooldown

    enforce_resend_cooldown flow: :unlock, redirect_to: :new_user_unlock_path

    def new
      super
      @email = params[:email].presence
      @resend_deadline = resend_deadline(:unlock, @email)
    end

    private

    def after_sending_unlock_instructions_path_for(_resource)
      new_user_unlock_path(email: resource.email)
    end
  end
end
