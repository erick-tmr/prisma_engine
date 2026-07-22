require "test_helper"

class AccountPasswordFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "signed-out users hitting /minha-conta/senha are sent to the sign-in page" do
    get account_password_path
    assert_redirected_to new_user_session_path
  end

  test "GET /minha-conta/senha renders three password fields" do
    sign_in users(:confirmed)
    get account_password_path
    assert_response :success
    assert_select "input[name='user[current_password]']"
    assert_select "input[name='user[password]']"
    assert_select "input[name='user[password_confirmation]']"
  end

  test "PATCH update with the right current_password rotates the password and keeps the session" do
    sign_in users(:confirmed)
    patch account_password_path, params: {
      user: {
        current_password: "password123",
        password: "nova-senha-456",
        password_confirmation: "nova-senha-456"
      }
    }
    assert_redirected_to account_password_path

    # Session retained: visiting a protected page does not redirect to sign-in.
    get account_profile_path
    assert_response :success

    # The new password is now the active one.
    assert users(:confirmed).reload.valid_password?("nova-senha-456")
  end

  test "PATCH update with the wrong current_password re-renders the form" do
    sign_in users(:confirmed)
    patch account_password_path, params: {
      user: {
        current_password: "errada",
        password: "nova-senha-456",
        password_confirmation: "nova-senha-456"
      }
    }
    assert_response :unprocessable_entity
    assert users(:confirmed).reload.valid_password?("password123")
  end
end
