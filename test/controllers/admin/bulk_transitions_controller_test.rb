require "test_helper"

module Admin
  class BulkTransitionsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers
    include ActiveJob::TestHelper

    test "non-admins are sent to the backoffice login" do
      post admin_bulk_transitions_path,
           params: { event: "to_production", order_numbers: [ orders(:confirmed_paid).number ] }
      assert_redirected_to admin_login_path
    end

    test "applies a plain transition and returns the per-order results" do
      sign_in users(:admin)
      order = orders(:confirmed_paid)

      post admin_bulk_transitions_path, params: { event: "to_production", order_numbers: [ order.number ] }

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal 1, body["done"]
      assert_equal "in_production", body["results"].first["status"]
      assert order.reload.in_production?
    end

    test "issue_label enqueues the batch label job" do
      sign_in users(:admin)
      order = orders(:producing)

      assert_enqueued_with(job: Shipping::EmitLabelsJob, args: [ [ order.id ] ]) do
        post admin_bulk_transitions_path, params: { event: "issue_label", order_numbers: [ order.number ] }
      end

      assert_response :success
      assert_equal 1, JSON.parse(response.body)["queued"]
    end
  end
end
