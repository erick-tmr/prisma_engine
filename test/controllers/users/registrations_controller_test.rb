require "test_helper"

module Users
  class RegistrationsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers
    include ActionMailer::TestHelper

    VALID_CPF = "52998224725"

    setup do
      @prev_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      ActionController::Base.cache_store.clear
      @holder = users(:unconfirmed).tap { |user| user.update_column(:phone, "(11) 98888-7777") }
    end

    teardown do
      Rails.cache = @prev_cache
    end

    def sign_up(**overrides)
      post user_registration_path, params: {
        user: {
          full_name: "Cliente Pendente",
          email: "certo@example.com",
          cpf: @holder.cpf,
          phone: "11988887777",
          password: "password123",
          password_confirmation: "password123"
        }.merge(overrides)
      }
    end

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

    test "signing up again with the CPF and password of a pending account corrects its e-mail in place" do
      delivered = capture_emails do
        assert_no_difference "User.count" do
          sign_up
        end
      end

      assert_equal [ [ "certo@example.com" ] ], delivered.map(&:to)
      assert_equal "certo@example.com", @holder.reload.email
      assert_redirected_to new_user_confirmation_path(email: "certo@example.com")
      assert_match "certo@example.com", flash[:notice]
      assert Rails.cache.read("resend:confirmation:certo@example.com").present?

      follow_redirect!
      assert_select "[data-email-edit]"
    end

    test "signing up again with the same e-mail resumes the pending account without sending anything" do
      assert_no_emails do
        sign_up(email: @holder.email)
      end

      assert_redirected_to new_user_confirmation_path(email: @holder.email)
      assert_nil flash[:notice]
    end

    test "the correction is refused when the new e-mail belongs to another account" do
      assert_no_emails do
        sign_up(email: users(:confirmed).email)
      end

      assert_response :unprocessable_entity
      assert_match(/E-mail/, response.body)
      assert_equal "pendente@example.com", @holder.reload.email
    end

    test "the CPF of a pending account is still taken without its password" do
      assert_no_difference "User.count" do
        sign_up(password: "outra-senha", password_confirmation: "outra-senha")
      end

      assert_response :unprocessable_entity
      assert_match(/CPF já está em uso/, response.body)
      assert_equal "pendente@example.com", @holder.reload.email
    end

    test "the CPF of a pending account whose confirmation window expired goes to the new signup" do
      @holder.update_column(:confirmation_sent_at, (User.confirm_within + 1.day).ago)

      sign_up(password: "outra-senha", password_confirmation: "outra-senha")

      assert_not User.exists?(@holder.id)
      assert_redirected_to new_user_confirmation_path(email: "certo@example.com")
      assert_equal @holder.cpf, User.find_by(email: "certo@example.com").cpf
    end

    test "signups are capped per address once the hourly limit is reached" do
      10.times { sign_up(cpf: "11111111111") }

      sign_up(cpf: "11111111111")

      assert_redirected_to new_user_registration_path
      assert_match(/Muitas solicitações/, flash[:alert])
    end
  end
end
