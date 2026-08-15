require "test_helper"

module Admin
  class ReturnsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup { @order = orders(:delivered) }

    test "non-admins cannot authorize a return" do
      post admin_order_return_path(@order.number)

      assert_redirected_to admin_login_path
      assert @order.reload.delivered?
    end

    test "an admin authorizes the return and the order enters the leg" do
      sign_in users(:admin)

      post admin_order_return_path(@order.number)

      assert_redirected_to admin_order_path(@order)
      assert @order.reload.awaiting_return?
      assert @order.return_shipment.inbound?
      assert_equal users(:admin), @order.status_changes.chronological.last.actor
    end

    test "the operator's service choice reaches the return shipment" do
      sign_in users(:admin)

      post admin_order_return_path(@order.number), params: { service: "sedex" }

      assert_equal "sedex", @order.reload.return_shipment.service
    end

    test "no service falls back to the default" do
      sign_in users(:admin)

      post admin_order_return_path(@order.number)

      assert_equal Shipping::DEFAULT_RETURN_SERVICE, @order.reload.return_shipment.service
    end

    test "a service Correios does not sell us is refused by name" do
      sign_in users(:admin)

      post admin_order_return_path(@order.number), params: { service: "teleport" }

      assert_equal I18n.t("admin.orders.returns.errors.invalid_service"), flash[:alert]
      assert @order.reload.delivered?
    end

    test "a refused authorization says why and changes nothing" do
      sign_in users(:admin)
      order = orders(:producing)

      post admin_order_return_path(order.number)

      assert_redirected_to admin_order_path(order)
      assert_equal I18n.t("admin.orders.returns.errors.not_returnable"), flash[:alert]
      assert order.reload.in_production?
    end

    test "an admin cancels the return and the order goes back to delivered" do
      sign_in users(:admin)
      Shipping::StartReturn.call(order: @order)

      delete admin_order_return_path(@order.number)

      assert_redirected_to admin_order_path(@order)
      assert @order.reload.delivered?
      assert_nil @order.return_shipment
    end

    test "a return already in the post cannot be cancelled" do
      sign_in users(:admin)
      Shipping::StartReturn.call(order: @order)
      @order.reload.return_shipment.update!(posted_at: Time.current)

      delete admin_order_return_path(@order.number)

      assert_equal I18n.t("admin.orders.returns.errors.already_posted"), flash[:alert]
      assert @order.reload.awaiting_return?
    end

    test "404s for an unknown order" do
      sign_in users(:admin)

      post admin_order_return_path("PG-00000")

      assert_response :not_found
    end
  end
end
