require "application_system_test_case"

class AuthLoginTest < ApplicationSystemTestCase
  test "a confirmed customer logs in through the form and sees the greeting" do
    user = users(:confirmed)
    visit new_user_session_path

    fill_in "user[email]", with: user.email
    fill_in "user[password]", with: "password123"
    find('input[type="submit"]').click

    assert_current_path root_path
    assert_text "Olá, #{user.first_name}"
  end
end
