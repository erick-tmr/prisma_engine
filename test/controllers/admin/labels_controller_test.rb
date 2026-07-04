require "test_helper"

module Admin
  class LabelsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers
    include ActiveJob::TestHelper

    test "non-admins are sent to the backoffice login" do
      post admin_labels_path, params: { order_numbers: [ orders(:producing).number ] }
      assert_redirected_to admin_login_path
    end

    test "enqueues the orchestrator for in_production orders and reports the count" do
      sign_in users(:admin)

      assert_enqueued_with(job: Shipping::EmitLabelsJob, args: [ [ orders(:producing).id ] ]) do
        post admin_labels_path,
             params: { order_numbers: [ orders(:producing).number, orders(:delivered).number ] }
      end

      assert_response :accepted
      assert_equal 1, response.parsed_body["enqueued"]
    end

    test "enqueues nothing when no selected order is in production" do
      sign_in users(:admin)

      assert_no_enqueued_jobs do
        post admin_labels_path, params: { order_numbers: [ orders(:delivered).number ] }
      end

      assert_response :accepted
      assert_equal 0, response.parsed_body["enqueued"]
    end

    test "non-admins cannot trigger emission for a single order" do
      post admin_label_path(orders(:producing).number)
      assert_redirected_to admin_login_path
    end

    test "schedules the per-order saga directly, without the orchestrator" do
      sign_in users(:admin)

      assert_enqueued_with(job: Shipping::CreatePrePostagemJob, args: [ orders(:producing).id ]) do
        post admin_label_path(orders(:producing).number)
      end

      assert_response :accepted
      assert_no_enqueued_jobs only: Shipping::EmitLabelsJob
      assert orders(:producing).reload.shipping_label.pending?
    end

    test "404s for a single order that is not in production" do
      sign_in users(:admin)

      assert_no_enqueued_jobs do
        post admin_label_path(orders(:delivered).number)
      end

      assert_response :not_found
    end

    test "non-admins cannot print a label sheet" do
      post admin_print_labels_path, params: { order_numbers: [ orders(:labeled).number ] }
      assert_redirected_to admin_login_path
    end

    test "print_sheet streams the composed PDF and reports the skipped count" do
      sign_in users(:admin)
      sheet = Shipping::LabelSheet::Result.new(pdf: "%PDF-1.4 stub", composed: 2, skipped: 1)

      Shipping::LabelSheet.stub(:call, sheet) do
        post admin_print_labels_path, params: { order_numbers: [ orders(:labeled).number ] }
      end

      assert_response :success
      assert_equal "application/pdf", response.media_type
      assert_equal "1", response.headers["X-Skipped-Count"]
      assert_match(/\A%PDF/, response.body)
    end

    test "print_sheet is unprocessable when no selected order has a ready label" do
      sign_in users(:admin)
      sheet = Shipping::LabelSheet::Result.new(pdf: "", composed: 0, skipped: 1)

      Shipping::LabelSheet.stub(:call, sheet) do
        post admin_print_labels_path, params: { order_numbers: [ orders(:producing).number ] }
      end

      assert_response :unprocessable_entity
    end
  end
end
