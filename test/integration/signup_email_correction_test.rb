require "test_helper"

class SignupEmailCorrectionTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  VALID_CPF = "52998224725".freeze

  setup do
    @prev_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    ActionController::Base.cache_store.clear
  end

  teardown do
    Rails.cache = @prev_cache
  end

  def sign_up(email: "errado@gmial.com")
    post user_registration_path, params: {
      user: { full_name: "Nova Cliente", email: email, cpf: VALID_CPF, phone: "11988887777",
              password: "password123", password_confirmation: "password123" }
    }
    User.find_by(cpf: VALID_CPF)
  end

  def correct_email(email)
    patch signup_email_path, params: { user: { email: email } }
  end

  test "the browser that signed up corrects the e-mail and gets a new link at the right address" do
    user = sign_up
    Rails.cache.clear

    delivered = capture_emails { correct_email("certo@gmail.com") }

    assert_equal [ [ "certo@gmail.com" ] ], delivered.map(&:to)
    assert_equal "certo@gmail.com", user.reload.email
    assert_not user.confirmed?
    assert_redirected_to new_user_confirmation_path(email: "certo@gmail.com")
    assert Rails.cache.read("resend:confirmation:certo@gmail.com").present?

    follow_redirect!
    assert_select "[data-email-edit]"
    assert_match "certo@gmail.com", response.body
  end

  test "the confirmation page offers the edit only to the browser that signed up" do
    sign_up

    get new_user_confirmation_path(email: "errado@gmial.com")
    assert_select "[data-email-edit]"
    assert_select "[data-email-edit-form][hidden]"

    reset!
    get new_user_confirmation_path(email: "errado@gmial.com")
    assert_select "[data-email-edit]", count: 0
    assert_match "errado@gmial.com", response.body
  end

  test "the confirmation page offers no edit for an address other than the one this browser signed up with" do
    sign_up

    get new_user_confirmation_path(email: users(:unconfirmed).email)

    assert_select "[data-email-edit]", count: 0
  end

  test "the confirmation page without an address offers no edit" do
    sign_up

    get new_user_confirmation_path

    assert_select "[data-email-edit]", count: 0
  end

  test "a browser that did not sign up cannot change any e-mail" do
    assert_no_emails { correct_email("intruso@example.com") }

    assert_redirected_to new_user_confirmation_path
    assert_equal "pendente@example.com", users(:unconfirmed).reload.email
  end

  test "an account confirmed in the meantime is no longer editable" do
    user = sign_up
    user.confirm

    assert_no_emails { correct_email("certo@gmail.com") }

    assert_redirected_to new_user_confirmation_path
    assert_equal "errado@gmial.com", user.reload.email
  end

  test "an address another account uses comes back as an alert and changes nothing" do
    user = sign_up

    assert_no_emails { correct_email(users(:confirmed).email) }

    assert_redirected_to new_user_confirmation_path(email: "errado@gmial.com")
    assert_match(/E-mail/, flash[:alert])
    assert_equal "errado@gmial.com", user.reload.email
  end

  test "corrections are capped per address once the hourly limit is reached" do
    sign_up
    5.times { |attempt| correct_email("tentativa#{attempt}@example.com") }

    correct_email("mais-uma@example.com")

    assert_redirected_to new_user_confirmation_path(email: "tentativa4@example.com")
    assert_match(/Muitas solicitações/, flash[:alert])
  end

  test "the cap also holds for a browser with no signup to correct" do
    6.times { correct_email("intruso@example.com") }

    assert_redirected_to new_user_confirmation_path
    assert_match(/Muitas solicitações/, flash[:alert])
  end
end
