module Users
  class RegistrationsController < Devise::RegistrationsController
    # Profile editing lives at /minha-conta/perfil — this Devise route stays
    # mounted only for sign-up (new/create). edit/update are dormant.
    def edit
      redirect_to account_profile_path
    end

    def update
      redirect_to account_profile_path
    end

    # Drop Devise's signed_up_but_unconfirmed flash on a successful (but
    # unconfirmed) signup — the confirm-email page we redirect to IS the
    # message, no need to repeat it above the page chrome.
    def create
      super
      flash.delete(:notice) if resource_signed_up_but_unconfirmed?
    end

    private

    def sign_up_params
      params.expect(user: [ :full_name, :email, :cpf, :phone,
                           :password, :password_confirmation ])
    end

    # Land newly-registered users on the confirm-email page (envelope hero +
    # instructions + resend) instead of dropping them on the home page with a
    # generic flash. Email travels in the URL so the page can show it in the
    # pill without storing per-user state.
    def after_inactive_sign_up_path_for(resource)
      new_user_confirmation_path(email: resource.email)
    end

    def resource_signed_up_but_unconfirmed?
      # Devise's build_resource runs inside super before we get here, so resource
      # is guaranteed non-nil — but it may be unsaved (validation failure).
      resource.persisted? && !resource.active_for_authentication?
    end
  end
end
