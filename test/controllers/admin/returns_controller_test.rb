require "test_helper"

module Admin
  class ReturnsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup { stub_return_quote }

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

    test "the operator's reason is recorded on the order" do
      sign_in users(:admin)

      post admin_order_return_path(@order.number), params: { reason: "Cartucho chegou riscado" }

      assert_equal "Cartucho chegou riscado", @order.reload.return_reason
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

    test "the operator can make the customer pay the return freight" do
      sign_in users(:admin)

      post admin_order_return_path(@order.number), params: { service: "pac", payer: "customer" }

      charge = @order.reload.return_shipment.freight_charge
      assert_equal 2140, charge.amount_cents
      assert_nil @order.return_shipping_label
    end

    test "a freight Correios will not quote is refused by name" do
      sign_in users(:admin)
      stub_return_quote({})

      post admin_order_return_path(@order.number), params: { payer: "customer" }

      assert_equal I18n.t("admin.orders.returns.errors.quote_unavailable"), flash[:alert]
      assert @order.reload.delivered?
    end

    test "the quote endpoint prices every service for the way back" do
      sign_in users(:admin)
      stub_return_quote(RETURN_QUOTE_PRICES.except("04227"))

      get admin_order_return_quote_path(@order.number)

      assert_response :ok
      assert_equal({ "price_cents" => 3270, "price_formatted" => "R$ 32,70" }, response.parsed_body["sedex"])
      assert_nil response.parsed_body["mini_envios"]
    end

    test "the quote endpoint reports Correios being down as a bad gateway" do
      sign_in users(:admin)
      stub_request(:post, "#{Correios::Api::BASE_URL}/preco/v1/nacional").to_return(status: 503, body: "down")

      get admin_order_return_quote_path(@order.number)

      assert_response :bad_gateway
    end

    test "an order that never shipped has nothing to quote" do
      sign_in users(:admin)
      order = bare_order

      get admin_order_return_quote_path(order.number)

      assert_response :not_found
    end

    test "non-admins cannot quote" do
      get admin_order_return_quote_path(@order.number)

      assert_redirected_to admin_login_path
    end
  end
end
