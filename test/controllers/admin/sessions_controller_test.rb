require "test_helper"

module Admin
  class SessionsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    test "GET /admin/entrar renders the login form" do
      get admin_login_path
      assert_response :success
      assert_select "form[action=?]", admin_session_path
      assert_select "input[name='user[email]']"
      assert_select "input[name='user[password]']"
    end

    test "admin credentials sign in and reach the dashboard" do
      post admin_session_path, params: { user: { email: users(:admin).email, password: "password123" } }
      assert_redirected_to admin_root_path

      get admin_root_path
      assert_response :success
    end

    test "a non-admin with valid credentials is rejected" do
      post admin_session_path, params: { user: { email: users(:confirmed).email, password: "password123" } }
      assert_response :unprocessable_entity
      assert_select "form[action=?]", admin_session_path

      get admin_root_path
      assert_redirected_to admin_login_path
    end

    test "an unknown email is rejected" do
      post admin_session_path, params: { user: { email: "ninguem@example.com", password: "password123" } }
      assert_response :unprocessable_entity
      assert_select "form[action=?]", admin_session_path
    end

    test "a wrong password is rejected" do
      post admin_session_path, params: { user: { email: users(:admin).email, password: "nope" } }
      assert_response :unprocessable_entity
      assert_select "form[action=?]", admin_session_path
    end

    test "an unconfirmed admin cannot sign in" do
      post admin_session_path, params: { user: { email: users(:unconfirmed_admin).email, password: "password123" } }
      assert_response :unprocessable_entity

      get admin_root_path
      assert_redirected_to admin_login_path
    end

    test "DELETE /admin/sair signs out and returns to the login" do
      sign_in users(:admin)
      delete admin_logout_path
      assert_redirected_to admin_login_path

      get admin_root_path
      assert_redirected_to admin_login_path
    end
  end
end
