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
      assert_equal "11988887777", user.phone
      assert_redirected_to root_path
    end

    test "POST /cadastrar without full_name re-renders the form with errors" do
      assert_no_difference "User.count" do
        post user_registration_path, params: {
          user: {
            full_name: "",
            email: "novo@example.com",
            cpf: VALID_CPF,
            password: "password123",
            password_confirmation: "password123"
          }
        }
      end
      assert_response :unprocessable_entity
      assert_match(/Nome completo/, response.body)
    end

    test "POST /cadastrar with an invalid CPF re-renders the form" do
      assert_no_difference "User.count" do
        post user_registration_path, params: {
          user: {
            full_name: "Novo Cliente",
            email: "novo@example.com",
            cpf: "11111111111",
            password: "password123",
            password_confirmation: "password123"
          }
        }
      end
      assert_response :unprocessable_entity
    end

    test "PATCH update changes the full_name when current_password matches" do
      sign_in users(:confirmed)
      patch user_registration_path, params: {
        user: {
          full_name: "Nome Atualizado",
          email: users(:confirmed).email,
          cpf: users(:confirmed).cpf,
          current_password: "password123"
        }
      }
      assert_redirected_to root_path
      assert_equal "Nome Atualizado", users(:confirmed).reload.full_name
    end
  end
end
