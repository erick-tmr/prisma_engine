module Account
  class ProfilesController < BaseController
    def edit
    end

    def update
      if current_user.update(profile_params)
        redirect_to account_profile_path, notice: t("account.profile.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def profile_params
      params.expect(user: %i[phone email])
    end
  end
end
