require "test_helper"

module Admin
  class ClientStrikesControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @client = users(:buyer)
      @strike = question_strikes(:spam_yellow_buyer)
    end

    test "signed-out visitors are sent to the backoffice login" do
      delete admin_client_strike_path(@client, @strike)
      assert_redirected_to admin_login_path
    end

    test "signed-in non-admins are sent to the backoffice login" do
      sign_in users(:confirmed)
      delete admin_client_strike_path(@client, @strike)
      assert_redirected_to admin_login_path
    end

    test "removing a strike releases the question and lands back on the client" do
      sign_in users(:admin)
      question = @strike.question

      assert_difference -> { @client.question_strikes.count }, -1 do
        delete admin_client_strike_path(@client, @strike)
      end

      assert_redirected_to admin_client_path(@client)
      assert_equal "awaiting_answer", question.reload.status
      assert_equal I18n.t("admin.clients.detail.strikes.removed"), flash[:notice]
    end

    test "a strike whose question already left spam reports the failure instead of a false success" do
      sign_in users(:admin)
      # The questions drawer lets an operator save a draft on a spam question, which moves it
      # to awaiting_answer and strands the strike. Moderate#release then skips.
      @strike.question.update!(status: "awaiting_answer")

      assert_no_difference -> { @client.question_strikes.count } do
        delete admin_client_strike_path(@client, @strike)
      end

      assert_redirected_to admin_client_path(@client)
      assert_nil flash[:notice]
      assert_equal I18n.t("admin.clients.detail.strikes.remove_failed"), flash[:alert]
    end

    test "a strike belonging to another client is out of reach" do
      sign_in users(:admin)

      other = client_with_strikes(1, name: "Outro Cliente", cpf: SPARE_CPFS[0])
      delete admin_client_strike_path(other, @strike)
      assert_response :not_found
    end
  end
end
