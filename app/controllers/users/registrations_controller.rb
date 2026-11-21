module Users
  class RegistrationsController < Devise::RegistrationsController
    include PendingSignup

    rate_limit to: 10, within: 1.hour, with: :too_many_signups, only: :create

    def edit
      redirect_to account_profile_path
    end

    def update
      redirect_to account_profile_path
    end

    def create
      holder = User.pending_signup(cpf: sign_up_params[:cpf], password: sign_up_params[:password])
      return correct_pending_signup(holder) if holder

      super
      return unless resource_signed_up_but_unconfirmed?

      flash.delete(:notice)
      remember_pending_signup(resource)
      record_resend_cooldown(:confirmation, resource.email)
    end

    private

    def sign_up_params
      params.expect(user: [ :full_name, :email, :cpf, :phone,
                           :password, :password_confirmation ])
    end

    def correct_pending_signup(holder)
      return if resume_pending_signup(holder, sign_up_params[:email])

      build_resource(sign_up_params)
      resource.errors.merge!(holder.errors)
      clean_up_passwords(resource)
      render :new, status: :unprocessable_entity
    end

    def too_many_signups
      redirect_to new_user_registration_path, alert: t("auth.resend.ip_limit")
    end

    def after_inactive_sign_up_path_for(resource)
      new_user_confirmation_path(email: resource.email)
    end

    def resource_signed_up_but_unconfirmed?
      resource.persisted? && !resource.active_for_authentication?
    end
  end
end
