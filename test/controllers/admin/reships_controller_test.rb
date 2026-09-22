require "test_helper"

module Admin
  class ReshipsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers
    include ActiveJob::TestHelper

    setup do
      @order = orders(:delivered)
      @order.shipment.update_columns(created_at: 1.day.ago)
      @order.update_columns(status: "returned")
      @order.status_changes.create!(from_status: "delivered", to_status: "returned", automatic: true)
    end

    test "non-admins cannot re-ship an order" do
      post admin_order_reship_path(@order.number)

      assert_redirected_to admin_login_path
      assert_empty @order.reload.past_shipments
    end

    test "an admin re-ships a returned order and the new label starts" do
      sign_in users(:admin)

      post admin_order_reship_path(@order.number)

      assert_redirected_to admin_order_path(@order)
      assert_equal I18n.t("admin.orders.reship.started"), flash[:notice]
      assert_equal 1, @order.reload.past_shipments.size
      assert_enqueued_with(job: Shipping::CreatePrePostagemJob, args: [ { shipment_id: @order.shipment.id } ])
    end

    test "the operator's service choice reaches the new despatch" do
      sign_in users(:admin)

      post admin_order_reship_path(@order.number), params: { service: "sedex" }

      assert_equal "sedex", @order.reload.shipment.service
    end

    test "an unknown service is refused by name" do
      sign_in users(:admin)

      post admin_order_reship_path(@order.number), params: { service: "carta" }

      assert_equal I18n.t("admin.orders.reship.errors.invalid_service"), flash[:alert]
      assert_empty @order.reload.past_shipments
    end

    test "an order that cannot be re-shipped is refused by name" do
      sign_in users(:admin)
      @order.update_columns(status: "delivered")

      post admin_order_reship_path(@order.number)

      assert_redirected_to admin_order_path(@order)
      assert_equal I18n.t("admin.orders.reship.errors.not_reshippable"), flash[:alert]
      assert_empty @order.reload.past_shipments
    end

    test "the order page offers the re-ship only to a returned order" do
      sign_in users(:admin)

      get admin_order_path(@order)

      assert_select "form[action=?]", admin_order_reship_path(@order.number) do
        assert_select "select[name=service] option[selected][value=?]", Shipping::DEFAULT_RETURN_SERVICE
      end
    end
  end
end
