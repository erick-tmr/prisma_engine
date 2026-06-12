require "test_helper"

class CheckoutTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "GET /checkout requires login" do
    get checkout_path
    assert_redirected_to new_user_session_path
  end

  test "GET /checkout renders the delivery + payment screen for signed-in users" do
    sign_in users(:confirmed)
    get checkout_path
    assert_response :success
    assert_match(/Entrega e pagamento/, response.body)
  end

  test "GET /checkout uses the minimal checkout chrome, not the storefront header" do
    sign_in users(:confirmed)
    get checkout_path
    # The reduced-exit-points layout shows the secure badge + stepper and
    # omits the storefront nav drawer toggle.
    assert_match(/Compra 100% segura/, response.body)
    assert_match(/Etapas do checkout/, response.body)
    assert_no_match(/data-toggle="drawer"/, response.body)
  end

  test "GET /checkout pre-selects the shipping service chosen on the cart" do
    sign_in users(:confirmed)
    post cart_finalize_path, params: { shipping_service: "pac" }
    get checkout_path
    assert_response :success
    assert_match(/data-preselected="pac"/, response.body)
  end
end
