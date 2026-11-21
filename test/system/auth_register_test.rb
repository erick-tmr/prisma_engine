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

  test "a visitor who mistyped the e-mail fixes it on the confirmation page" do
    visit new_user_registration_path

    fill_in "user[full_name]", with: "Nova Cliente"
    fill_in "user[email]", with: "nova@gmial.com"
    fill_in "user[cpf]", with: VALID_CPF
    fill_in "user[phone]", with: "11999990000"
    fill_in "user[password]", with: "password123"
    fill_in "user[password_confirmation]", with: "password123"
    find('input[type="submit"]').click

    find("[data-email-edit-open]").click
    within("[data-email-edit-form]") do
      fill_in "user[email]", with: "nova@gmail.com"
      find('button[type="submit"]').click
    end

    assert_selector "[data-email-edit-view]", text: "nova@gmail.com"
    assert_equal "nova@gmail.com", User.find_by(cpf: VALID_CPF).email
  end
end
