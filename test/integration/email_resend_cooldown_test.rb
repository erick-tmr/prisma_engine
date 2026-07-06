require "test_helper"

class EmailResendCooldownTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  VALID_CPF = "52998224725"

  setup do
    @prev_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rails.cache = @prev_cache
  end

  test "a first password-reset request sends the mail, records the cooldown, and shows the countdown" do
    email = users(:confirmed).email

    assert_difference "ActionMailer::Base.deliveries.size", 1 do
      post user_password_path, params: { user: { email: email } }
    end
    assert_redirected_to new_user_password_path(email: email)
    assert Rails.cache.read("resend:password:#{email}").present?

    follow_redirect!
    assert_match(/data-resend-deadline=/, response.body)
    assert_match(/data-resend-submit/, response.body)
  end

  test "a second password-reset request within the cooldown is blocked without sending" do
    email = users(:confirmed).email
    post user_password_path, params: { user: { email: email } }

    assert_no_difference "ActionMailer::Base.deliveries.size" do
      post user_password_path, params: { user: { email: email } }
    end
    assert_redirected_to new_user_password_path(email: email)
    assert_match(/aguarde/i, flash[:alert].to_s)
  end

  test "a blank email skips the cooldown guard and records nothing" do
    assert_no_difference "ActionMailer::Base.deliveries.size" do
      post user_password_path, params: { user: { email: "" } }
    end
    assert_response :redirect
    assert_nil Rails.cache.read("resend:password:")
  end

  test "the per-IP cap blocks further requests once the hourly limit is reached" do
    EmailResendCooldown::IP_CAP.times do |i|
      post user_password_path, params: { user: { email: "spam#{i}@example.com" } }
    end

    post user_password_path, params: { user: { email: "over-the-cap@example.com" } }

    assert_redirected_to new_user_password_path(email: "over-the-cap@example.com")
    assert_match(/muitas solicita/i, flash[:alert].to_s)
    assert_nil Rails.cache.read("resend:password:over-the-cap@example.com")
  end

  test "resending confirmation sends the mail and returns to the confirm page" do
    email = users(:unconfirmed).email

    assert_difference "ActionMailer::Base.deliveries.size", 1 do
      post user_confirmation_path, params: { user: { email: email } }
    end
    assert_redirected_to new_user_confirmation_path(email: email)
    assert Rails.cache.read("resend:confirmation:#{email}").present?
  end

  test "registering records the confirmation cooldown so the confirm page counts down from the start" do
    post user_registration_path, params: {
      user: {
        full_name: "Nova Conta", email: "novaconta@example.com", cpf: VALID_CPF,
        phone: "11999990000", password: "password123", password_confirmation: "password123"
      }
    }

    assert_redirected_to new_user_confirmation_path(email: "novaconta@example.com")
    assert Rails.cache.read("resend:confirmation:novaconta@example.com").present?

    follow_redirect!
    assert_match(/data-resend-deadline=/, response.body)
  end

  test "requesting unlock instructions sends the mail and returns to the unlock page" do
    email = users(:locked).email

    assert_difference "ActionMailer::Base.deliveries.size", 1 do
      post user_unlock_path, params: { user: { email: email } }
    end
    assert_redirected_to new_user_unlock_path(email: email)
    assert Rails.cache.read("resend:unlock:#{email}").present?
  end

  test "the unlock page renders under the styled auth layout" do
    get new_user_unlock_path
    assert_response :success
    assert_select "form input[type=email][name='user[email]']"
    assert_select "[data-resend-submit]"
  end
end
