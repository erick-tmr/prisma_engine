require "test_helper"

module Admin
  class QuestionBulkActionsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    def bulk(event, questions)
      post admin_question_bulk_actions_path,
           params: { event: event, question_ids: Array(questions).map(&:id) },
           headers: { "Accept" => "application/json" }
    end

    test "non-admins are sent to the backoffice login" do
      bulk("archive", questions(:awaiting_yellow))

      assert_redirected_to admin_login_path
    end

    test "archiving a selection reports what it did" do
      sign_in users(:admin)
      bulk("archive", [ questions(:awaiting_yellow), questions(:draft_yellow) ])

      assert_response :success
      body = response.parsed_body

      assert_equal 2, body["done"]
      assert_equal "2 perguntas arquivadas e fora da loja.", body["message"]
      assert_predicate questions(:awaiting_yellow).reload, :archived?
    end

    test "marking a selection as spam strikes each account once" do
      sign_in users(:admin)

      assert_difference -> { QuestionStrike.count }, 1 do
        bulk("spam", questions(:awaiting_yellow))
      end

      assert_equal "1 pergunta marcada como spam.", response.parsed_body["message"]
    end

    test "an already moderated question is skipped rather than struck again" do
      sign_in users(:admin)
      bulk("spam", questions(:spam_yellow))
      body = response.parsed_body

      assert_equal 0, body["done"]
      assert_equal 1, body["skipped"]
      assert_equal "already_spam", body["results"].first["reason"]
    end

    test "releasing a selection puts the questions back on the storefront" do
      sign_in users(:admin)
      bulk("release", questions(:spam_yellow))

      assert_equal "1 pergunta liberada, já aparece na página do produto.", response.parsed_body["message"]
      assert_predicate questions(:spam_yellow).reload, :awaiting_answer?
    end

    test "answering is not something the bulk bar can do" do
      sign_in users(:admin)
      bulk("answer", questions(:awaiting_yellow))
      body = response.parsed_body

      assert_equal 0, body["done"]
      assert_equal "unknown_event", body["results"].first["reason"]
      assert_equal "Nenhuma pergunta foi alterada.", body["message"]
      assert_predicate questions(:awaiting_yellow).reload, :awaiting_answer?
    end

    test "an empty selection is a no-op" do
      sign_in users(:admin)
      post admin_question_bulk_actions_path, params: { event: "archive" }, headers: { "Accept" => "application/json" }

      assert_response :success
      assert_empty response.parsed_body["results"]
    end
  end
end
