require "test_helper"

module Admin
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    test "signed-out visitors are sent to the backoffice login" do
      get admin_root_path
      assert_redirected_to admin_login_path
    end

    test "signed-in non-admins are sent to the backoffice login" do
      sign_in users(:confirmed)
      get admin_root_path
      assert_redirected_to admin_login_path
    end

    test "signed-in admins see the dashboard" do
      sign_in users(:admin)
      get admin_root_path
      assert_response :success
      assert_select "h1"
    end
  end
end
