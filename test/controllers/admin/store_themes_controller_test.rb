require "test_helper"

module Admin
  class StoreThemesControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup { @setting = store_settings(:default) }

    test "non-admins are sent to the backoffice login" do
      get admin_store_theme_path

      assert_redirected_to admin_login_path
    end

    test "the page shows the date pickers and the current status" do
      sign_in users(:admin)

      get admin_store_theme_path

      assert_response :success
      assert_select "form[data-schedule][data-schedule-empty=?]", "Selecione o período"
      assert_select "input[type=hidden][name=?][data-schedule-value=start]", "store_setting[black_friday_starts_at]"
      assert_select "input[type=hidden][name=?][data-schedule-value=end]", "store_setting[black_friday_ends_at]"
      assert_select "[data-schedule-cals]"
      assert_select "input[data-schedule-time]", count: 2
      assert_select "[data-theme-status]", text: "Desligado"
      assert_select "form[data-confirm]", count: 0
      assert_select "link[href*=?]", "themes/black-friday", count: 0
    end

    test "a scheduled window shows when it starts and offers the turn-off button" do
      @setting.update!(black_friday_starts_at: 1.day.from_now)
      sign_in users(:admin)

      get admin_store_theme_path

      assert_select "[data-theme-status]", text: /Agendado para/
      assert_select "input[name=?][value=?]", "store_setting[black_friday_starts_at]",
                    @setting.black_friday_starts_at.strftime("%Y-%m-%dT%H:%M")
      assert_select "form[data-confirm]"
    end

    test "saving a window reads the pickers in Brasília time" do
      sign_in users(:admin)

      patch admin_store_theme_path, params: { store_setting: {
        black_friday_starts_at: "2026-11-27T00:00", black_friday_ends_at: "2026-12-01T00:00"
      } }

      assert_redirected_to admin_store_theme_path
      assert_equal "Agendamento do tema salvo.", flash[:notice]
      assert_equal Time.utc(2026, 11, 27, 3), @setting.reload.black_friday_starts_at
      assert_equal Time.utc(2026, 12, 1, 3), @setting.black_friday_ends_at
    end

    test "a window that ends before it starts comes back with the reason" do
      sign_in users(:admin)

      patch admin_store_theme_path, params: { store_setting: {
        black_friday_starts_at: "2026-12-01T00:00", black_friday_ends_at: "2026-11-27T00:00"
      } }

      assert_redirected_to admin_store_theme_path
      assert_match(/precisa ser depois do início/, flash[:alert])
      assert_nil @setting.reload.black_friday_starts_at
    end

    test "turning it off clears the window" do
      @setting.update!(black_friday_starts_at: 1.day.ago, black_friday_ends_at: 1.day.from_now)
      sign_in users(:admin)

      delete admin_store_theme_path

      assert_redirected_to admin_store_theme_path
      assert_nil @setting.reload.black_friday_starts_at
      assert_nil @setting.black_friday_ends_at
    end
  end
end
