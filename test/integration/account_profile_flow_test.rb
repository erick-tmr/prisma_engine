require "test_helper"

class AccountProfileFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "signed-out users hitting /minha-conta/perfil are sent to the sign-in page" do
    get account_profile_path
    assert_redirected_to new_user_session_path
  end

  test "the bare /minha-conta root redirects to /perfil" do
    sign_in users(:confirmed)
    get account_root_path
    assert_redirected_to "/minha-conta/perfil"
    follow_redirect!
    assert_response :success
  end

  test "GET /minha-conta/perfil renders the profile with full_name and cpf as read-only text" do
    sign_in users(:confirmed)
    get account_profile_path
    assert_response :success
    assert_select "form input[type=email][name='user[email]']"
    assert_select "form input[name='user[phone]'][data-mask-phone]"
    # full_name and cpf are paragraphs, never inputs
    assert_select "form input[name='user[full_name]']", count: 0
    assert_select "form input[name='user[cpf]']", count: 0
    assert_match(/Cliente Confirmado/, response.body)
    assert_match(/111\.?444\.?777-?35|11144477735/, response.body)
  end

  test "PATCH update saves a new phone" do
    sign_in users(:confirmed)
    patch account_profile_path, params: { user: { phone: "11912345678", email: users(:confirmed).email } }
    assert_redirected_to account_profile_path
    assert_equal "11912345678", users(:confirmed).reload.phone
  end

  test "PATCH update with an invalid email re-renders the form" do
    sign_in users(:confirmed)
    patch account_profile_path, params: { user: { phone: users(:confirmed).phone, email: "not-an-email" } }
    assert_response :unprocessable_entity
  end

  test "attempting to change full_name via the profile params is silently dropped" do
    sign_in users(:confirmed)
    original = users(:confirmed).full_name
    patch account_profile_path, params: {
      user: { phone: users(:confirmed).phone, email: users(:confirmed).email, full_name: "Hacker" }
    }
    assert_redirected_to account_profile_path
    assert_equal original, users(:confirmed).reload.full_name
  end

  test "attempting to change cpf via the profile params is silently dropped" do
    sign_in users(:confirmed)
    original = users(:confirmed).cpf
    patch account_profile_path, params: {
      user: { phone: users(:confirmed).phone, email: users(:confirmed).email, cpf: "99999999999" }
    }
    assert_redirected_to account_profile_path
    assert_equal original, users(:confirmed).reload.cpf
  end

  test "PATCH update with a new email triggers reconfirmation + change notification" do
    sign_in users(:confirmed)
    # Two mails: reconfirmation to the new address + the email-changed
    # notification to the old address (Devise `email_changed_notification`).
    assert_difference "ActionMailer::Base.deliveries.size", 2 do
      patch account_profile_path, params: {
        user: { phone: users(:confirmed).phone, email: "novo-email@example.com" }
      }
    end
    assert_redirected_to account_profile_path
    user = users(:confirmed).reload
    # Devise reconfirmable keeps the original email active until the link is clicked
    assert_equal "confirmed@example.com", user.email
    assert_equal "novo-email@example.com", user.unconfirmed_email
  end

  test "GET /minha-conta/perfil shows the pending email banner once reconfirmation is open" do
    user = users(:confirmed)
    user.update!(unconfirmed_email: "pendente@example.com")
    sign_in user
    get account_profile_path
    assert_match(/pendente@example\.com/, response.body)
  end
end
