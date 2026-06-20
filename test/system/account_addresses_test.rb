require "application_system_test_case"

class AccountAddressesTest < ApplicationSystemTestCase
  setup do
    Rails.cache.clear
    stub_external_env
    stub_cep
    login_as_user(users(:orderless))
  end

  teardown { restore_external_env }

  test "the CEP blur autofills the address and the form saves" do
    visit new_account_address_path

    check "receiver_self"
    assert_field "address[receiver_name]", with: users(:orderless).full_name

    fill_in "address[zip]", with: "01310100"
    find('[name="address[number]"]').click

    assert_field "address[street]", with: "Av. Paulista"
    assert_field "address[neighborhood]", with: "Bela Vista"
    assert_field "address[city]", with: "São Paulo"

    fill_in "address[number]", with: "1578"
    find('input[type="submit"]').click

    assert_current_path account_addresses_path
    assert_text "Av. Paulista"
  end
end
