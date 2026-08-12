require "test_helper"

module Users
  class RegistrationsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    VALID_CPF = "52998224725"

    test "POST /cadastrar with valid params creates an unconfirmed user" do
      assert_difference "User.count", 1 do
        assert_difference "ActionMailer::Base.deliveries.size", 1 do
          post user_registration_path, params: {
            user: {
              full_name: "Novo Cliente",
              email: "novo@example.com",
              cpf: VALID_CPF,
              phone: "11988887777",
              password: "password123",
              password_confirmation: "password123"
            }
          }
        end
      end

      user = User.find_by(email: "novo@example.com")
      assert_not_nil user
      assert_nil user.confirmed_at, "user should remain unconfirmed until they click the link"
      assert_equal "(11) 98888-7777", user.phone
      # Devise's generic flash is suppressed in favor of the dedicated page,
      # which receives the email via query string to populate its pill.
      assert_redirected_to new_user_confirmation_path(email: "novo@example.com")
      assert_nil flash[:notice]
    end

    test "POST /cadastrar without full_name re-renders the form with errors" do
      assert_no_difference "User.count" do
        post user_registration_path, params: {
          user: {
            full_name: "",
            email: "novo@example.com",
            cpf: VALID_CPF,
            phone: "11988887777",
            password: "password123",
            password_confirmation: "password123"
          }
        }
      end
      assert_response :unprocessable_entity
      assert_match(/Nome completo/, response.body)
    end

    test "POST /cadastrar without phone re-renders the form with errors" do
      assert_no_difference "User.count" do
        post user_registration_path, params: {
          user: {
            full_name: "Novo Cliente",
            email: "novo@example.com",
            cpf: VALID_CPF,
            phone: "",
            password: "password123",
            password_confirmation: "password123"
          }
        }
      end
      assert_response :unprocessable_entity
      assert_match(/Celular/, response.body)
    end

    test "POST /cadastrar with an invalid CPF re-renders the form" do
      assert_no_difference "User.count" do
        post user_registration_path, params: {
          user: {
            full_name: "Novo Cliente",
            email: "novo@example.com",
            cpf: "11111111111",
            phone: "11988887777",
            password: "password123",
            password_confirmation: "password123"
          }
        }
      end
      assert_response :unprocessable_entity
    end

    test "GET /editar redirects to /minha-conta/perfil (Devise edit route is dormant)" do
      sign_in users(:confirmed)
      get edit_user_registration_path
      assert_redirected_to account_profile_path
    end

    test "PATCH update redirects to /minha-conta/perfil and does not change profile fields" do
      sign_in users(:confirmed)
      original_full_name = users(:confirmed).full_name
      patch user_registration_path, params: {
        user: { full_name: "Nope", current_password: "password123" }
      }
      assert_redirected_to account_profile_path
      assert_equal original_full_name, users(:confirmed).reload.full_name
    end
  end
end
