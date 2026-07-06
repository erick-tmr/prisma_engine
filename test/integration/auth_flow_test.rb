require "test_helper"

class AuthFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  VALID_CPF = "52998224725"

  test "GET /entrar renders the sign-in form" do
    get new_user_session_path
    assert_response :success
    assert_select "form input[type=email]"
    assert_select "form input[type=password]"
  end

  test "GET /cadastrar renders the registration form with masked CPF and phone" do
    get new_user_registration_path
    assert_response :success
    assert_select "input[name='user[cpf]'][data-mask-cpf]"
    assert_select "input[name='user[phone]'][data-mask-phone]"
    assert_select "input[name='user[full_name]']"
  end

  test "GET /recuperar-senha/new renders the forgot-password form" do
    get new_user_password_path
    assert_response :success
    assert_select "form input[type=email]"
  end

  test "GET /confirmar/new without an email param shows the manual input" do
    get new_user_confirmation_path
    assert_response :success
    assert_select "form input[type=email][name='user[email]']"
    # No email pill since we don't know the address
    assert_no_match(/email-pill/, response.body)
  end

  test "GET /confirmar/new?email=... renders the address in a pill" do
    get new_user_confirmation_path(email: "novo@example.com")
    assert_response :success
    assert_match(/novo@example\.com/, response.body)
    assert_match(/email-pill/, response.body)
    # Hidden input carries the email through the resend POST
    assert_select "form input[type=hidden][name='user[email]'][value='novo@example.com']"
  end

  test "POST /recuperar-senha enqueues a reset-password mail for an existing email" do
    assert_difference "ActionMailer::Base.deliveries.size", 1 do
      post user_password_path, params: { user: { email: users(:confirmed).email } }
    end
    assert_redirected_to new_user_password_path(email: users(:confirmed).email)
  end

  test "POST /entrar with an unconfirmed account is rejected with a pt-BR flash" do
    post user_session_path, params: {
      user: { email: users(:unconfirmed).email, password: "password123" }
    }
    assert_redirected_to new_user_session_path
    assert_match(/confirme a sua conta/i, flash[:alert].to_s)
  end

  test "POST /entrar with confirmed credentials redirects and shows the greeting" do
    user = users(:confirmed)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
    assert_redirected_to root_path
    follow_redirect!
    assert_match(/Olá, #{user.first_name}/, response.body)
  end

  test "DELETE /sair signs the user out and reverts the header" do
    sign_in users(:confirmed)
    delete destroy_user_session_path
    follow_redirect!
    assert_select "a[href='#{new_user_session_path}']"
    assert_no_match(/Olá,/, response.body)
  end

  test "the storefront home shows the sign-in link when signed out" do
    get root_path
    assert_response :success
    assert_select "a[href='#{new_user_session_path}']"
  end
end
