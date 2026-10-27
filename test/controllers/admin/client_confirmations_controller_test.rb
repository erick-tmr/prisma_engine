require "test_helper"

module Admin
  class ClientConfirmationsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers
    include ActionMailer::TestHelper

    test "signed-out visitors are sent to the backoffice login" do
      assert_no_emails do
        post admin_client_confirmation_path(users(:unconfirmed))
      end
      assert_redirected_to admin_login_path
    end

    test "signed-in non-admins are sent to the backoffice login" do
      sign_in users(:confirmed)
      assert_no_emails do
        post admin_client_confirmation_path(users(:unconfirmed))
      end
      assert_redirected_to admin_login_path
    end

    test "a pending client gets a fresh confirmation link at their current e-mail" do
      sign_in users(:admin)
      client = users(:unconfirmed)
      client.update_columns(confirmation_token: "stale-token", confirmation_sent_at: 30.days.ago)

      delivered = capture_emails { post admin_client_confirmation_path(client) }

      assert_redirected_to admin_client_path(client)
      assert_equal "Enviamos um novo link de confirmação para #{client.email}. " \
                   "Peça ao cliente para abrir o e-mail (vale conferir o spam) e clicar no link.", flash[:notice]
      assert_equal [ [ client.email ] ], delivered.map(&:to)
      assert_equal "Instruções de confirmação", delivered.first.subject
      client.reload
      assert_not_equal "stale-token", client.confirmation_token
      assert_in_delta Time.current, client.confirmation_sent_at, 5.seconds
      assert_nil client.confirmed_at
    end

    test "a link still inside its window is replaced too, restarting the window and killing the old one" do
      sign_in users(:admin)
      client = users(:unconfirmed)
      client.update_columns(confirmation_token: "live-token", confirmation_sent_at: 2.days.ago)

      delivered = capture_emails { post admin_client_confirmation_path(client) }

      client.reload
      assert_not_equal "live-token", client.confirmation_token
      assert_in_delta Time.current, client.confirmation_sent_at, 5.seconds
      assert_includes delivered.first.html_part.body.to_s, "confirmation_token=#{client.confirmation_token}"
      assert_nil User.find_by(confirmation_token: "live-token")
    end

    test "an already confirmed client gets nothing and the operator is told why" do
      sign_in users(:admin)
      client = users(:confirmed)

      assert_no_emails do
        post admin_client_confirmation_path(client)
      end

      assert_redirected_to admin_client_path(client)
      assert_equal "Esta conta já está confirmada, então nenhum link foi enviado.", flash[:alert]
    end

    test "an admin account is not reachable as a client" do
      sign_in users(:admin)
      post admin_client_confirmation_path(users(:admin))

      assert_response :not_found
    end
  end
end
