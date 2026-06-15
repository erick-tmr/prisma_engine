module Admin
  class SessionsController < ApplicationController
    layout "admin"

    def new
    end

    def create
      user = User.find_for_database_authentication(email: params.dig(:user, :email))
      if valid_admin_login?(user)
        user.remember_me = ActiveModel::Type::Boolean.new.cast(params.dig(:user, :remember_me))
        sign_in(:user, user)
        redirect_to admin_root_path
      else
        flash.now[:alert] = t("admin.sessions.failure")
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      sign_out(:user)
      redirect_to admin_login_path
    end

    private

    def valid_admin_login?(user)
      user&.admin? &&
        user.valid_for_authentication? { user.valid_password?(params.dig(:user, :password)) } &&
        user.active_for_authentication?
    end
  end
end
