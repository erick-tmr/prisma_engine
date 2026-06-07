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

    private

    def sign_up_params
      params.expect(user: [ :full_name, :email, :cpf, :phone,
                           :password, :password_confirmation ])
    end
  end
end
