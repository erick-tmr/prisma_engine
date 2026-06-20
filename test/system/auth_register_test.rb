require "application_system_test_case"

class AuthRegisterTest < ApplicationSystemTestCase
  VALID_CPF = "52998224725".freeze

  test "a visitor registers and is asked to confirm their email" do
    visit new_user_registration_path

    fill_in "user[full_name]", with: "Nova Cliente"
    fill_in "user[email]", with: "nova@example.com"
    fill_in "user[cpf]", with: VALID_CPF
    fill_in "user[phone]", with: "11999990000"
    fill_in "user[password]", with: "password123"
    fill_in "user[password_confirmation]", with: "password123"
    find('input[type="submit"]').click

    assert_text(/confirma/i)
    assert_no_text "Olá,"
    assert User.exists?(email: "nova@example.com")
  end
end
