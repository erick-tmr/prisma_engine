require "test_helper"

module Admin
  class ReturnChargesControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers
    include ActionMailer::TestHelper

    setup do
      stub_return_quote
      @order = orders(:delivered)
      Shipping::StartReturn.call(order: @order, payer: "customer")
      @charge = @order.reload.return_shipment.freight_charge
    end

    test "non-admins cannot touch the charge" do
      post admin_waive_order_return_charge_path(@order.number)

      assert_redirected_to admin_login_path
      assert_nil @charge.reload.voided_at
    end

    test "the store assumes the freight" do
      sign_in users(:admin)

      post admin_waive_order_return_charge_path(@order.number)

      assert_redirected_to admin_order_path(@order)
      assert_equal I18n.t("admin.orders.return_charges.waived"), flash[:notice]
      assert @charge.reload.voided_at
    end

    test "the charge is mailed again" do
      sign_in users(:admin)

      assert_enqueued_emails 1 do
        post admin_resend_order_return_charge_path(@order.number)
      end

      assert_equal I18n.t("admin.orders.return_charges.resent"), flash[:notice]
    end

    test "an expired charge is renewed" do
      sign_in users(:admin)
      @charge.update!(expires_at: 1.minute.ago)

      assert_difference -> { ReturnFreightCharge.count }, 1 do
        post admin_order_return_charge_path(@order.number)
      end

      assert_equal I18n.t("admin.orders.return_charges.renewed"), flash[:notice]
    end

    test "a refused action says why" do
      sign_in users(:admin)

      post admin_order_return_charge_path(@order.number)

      assert_redirected_to admin_order_path(@order)
      assert_equal I18n.t("admin.orders.return_charges.errors.no_charge"), flash[:alert]
    end
  end
end
