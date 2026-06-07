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

  test "GET /confirmar/new renders the resend-confirmation form" do
    get new_user_confirmation_path
    assert_response :success
    assert_select "form input[type=email]"
  end

  test "POST /recuperar-senha enqueues a reset-password mail for an existing email" do
    assert_difference "ActionMailer::Base.deliveries.size", 1 do
      post user_password_path, params: { user: { email: users(:confirmed).email } }
    end
    assert_redirected_to new_user_session_path
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
    assert_match(/Entrar/, response.body)
    assert_no_match(/Olá,/, response.body)
  end

  test "the storefront home shows the sign-in link when signed out" do
    get root_path
    assert_response :success
    assert_select "a[href='#{new_user_session_path}']"
  end
end
