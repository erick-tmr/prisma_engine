module Admin
  class StoreThemesController < BaseController
    before_action :set_setting

    def edit; end

    def update
      if @setting.update(theme_params)
        redirect_to admin_store_theme_path, notice: t("admin.theme.flash.saved")
      else
        redirect_to admin_store_theme_path, alert: @setting.errors.full_messages.to_sentence
      end
    end

    def destroy
      @setting.turn_off_black_friday!
      redirect_to admin_store_theme_path, notice: t("admin.theme.flash.turned_off")
    end

    private

    def set_setting
      @setting = StoreSetting.current
    end

    def theme_params
      params.expect(store_setting: [ :black_friday_starts_at, :black_friday_ends_at ])
    end
  end
end
