module Users
  class RegistrationsController < Devise::RegistrationsController
    private

    def sign_up_params
      params.expect(user: [ :full_name, :email, :cpf, :phone,
                           :password, :password_confirmation ])
    end

    def account_update_params
      params.expect(user: [ :full_name, :email, :cpf, :phone,
                           :password, :password_confirmation, :current_password ])
    end
  end
end
