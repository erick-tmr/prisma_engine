module Users
  class RegistrationsController < Devise::RegistrationsController
    include EmailResendCooldown

    def edit
      redirect_to account_profile_path
    end

    def update
      redirect_to account_profile_path
    end

    def create
      super
      return unless resource_signed_up_but_unconfirmed?

      flash.delete(:notice)
      record_resend_cooldown(:confirmation, resource.email)
    end

    private

    def sign_up_params
      params.expect(user: [ :full_name, :email, :cpf, :phone,
                           :password, :password_confirmation ])
    end

    def after_inactive_sign_up_path_for(resource)
      new_user_confirmation_path(email: resource.email)
    end

    def resource_signed_up_but_unconfirmed?
      resource.persisted? && !resource.active_for_authentication?
    end
  end
end
