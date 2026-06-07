require "test_helper"

class AccountAddressesFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def valid_attrs(overrides = {})
    {
      zip: "01310-100",
      street: "Avenida Paulista",
      number: "1578",
      complement: "Conj. 12",
      neighborhood: "Bela Vista",
      city: "São Paulo",
      state: "SP"
    }.merge(overrides)
  end

  test "signed-out users hitting /minha-conta/enderecos are sent to the sign-in page" do
    get account_addresses_path
    assert_redirected_to new_user_session_path
  end

  test "GET index shows the empty state when the user has no addresses" do
    sign_in users(:confirmed)
    get account_addresses_path
    assert_response :success
    assert_match(/Você ainda não tem endereços cadastrados/, response.body)
  end

  test "creating a first address marks it default automatically" do
    sign_in users(:confirmed)
    assert_difference "users(:confirmed).addresses.count", 1 do
      post account_addresses_path, params: { address: valid_attrs }
    end
    address = users(:confirmed).addresses.last
    assert address.default?
    # CEP normalized to 8 digits
    assert_equal "01310100", address.zip
    assert_redirected_to account_addresses_path
  end

  test "second address does not become default automatically" do
    sign_in users(:confirmed)
    users(:confirmed).addresses.create!(valid_attrs)
    post account_addresses_path, params: { address: valid_attrs(street: "Outra Rua") }
    assert_not users(:confirmed).addresses.order(:id).last.default?
  end

  test "creating an invalid address re-renders the new form" do
    sign_in users(:confirmed)
    post account_addresses_path, params: { address: valid_attrs(state: "XX") }
    assert_response :unprocessable_entity
  end

  test "GET new renders the address form" do
    sign_in users(:confirmed)
    get new_account_address_path
    assert_response :success
    assert_select "input[name='address[zip]']"
    assert_select "select[name='address[state]']"
  end

  test "GET edit pre-fills the address" do
    sign_in users(:confirmed)
    address = users(:confirmed).addresses.create!(valid_attrs)
    get edit_account_address_path(address)
    assert_response :success
    assert_select "input[name='address[street]'][value='Avenida Paulista']"
  end

  test "PATCH update saves changes" do
    sign_in users(:confirmed)
    address = users(:confirmed).addresses.create!(valid_attrs)
    patch account_address_path(address), params: { address: valid_attrs(complement: "Nova sala") }
    assert_redirected_to account_addresses_path
    assert_equal "Nova sala", address.reload.complement
  end

  test "PATCH update with invalid data re-renders" do
    sign_in users(:confirmed)
    address = users(:confirmed).addresses.create!(valid_attrs)
    patch account_address_path(address), params: { address: valid_attrs(state: "XX") }
    assert_response :unprocessable_entity
  end

  test "DELETE removes the address" do
    sign_in users(:confirmed)
    address = users(:confirmed).addresses.create!(valid_attrs)
    assert_difference "users(:confirmed).addresses.count", -1 do
      delete account_address_path(address)
    end
    assert_redirected_to account_addresses_path
  end

  test "PATCH default flips the previous default off" do
    sign_in users(:confirmed)
    first = users(:confirmed).addresses.create!(valid_attrs)
    second = users(:confirmed).addresses.create!(valid_attrs(street: "Outra"))
    patch default_account_address_path(second)
    assert_redirected_to account_addresses_path
    assert second.reload.default?
    assert_not first.reload.default?
  end

  test "trying to access another user's address raises not-found" do
    other = User.create!(
      email: "other@example.com",
      password: "password123",
      password_confirmation: "password123",
      full_name: "Outro Cliente",
      cpf: "52998224725",
      confirmed_at: 1.day.ago
    )
    others_address = other.addresses.create!(valid_attrs)
    sign_in users(:confirmed)
    get edit_account_address_path(others_address)
    assert_response :not_found
  end

  test "index shows the default badge and a Tornar padrão button for non-defaults" do
    sign_in users(:confirmed)
    users(:confirmed).addresses.create!(valid_attrs)
    users(:confirmed).addresses.create!(valid_attrs(street: "Outra"))
    get account_addresses_path
    assert_response :success
    assert_match(/Padrão/, response.body)
    assert_match(/Tornar padrão/, response.body)
  end

  test "the formatted CEP appears in the address card" do
    sign_in users(:confirmed)
    users(:confirmed).addresses.create!(valid_attrs)
    get account_addresses_path
    assert_match(/01310-100/, response.body)
  end
end
