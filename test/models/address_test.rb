require "test_helper"

class AddressTest < ActiveSupport::TestCase
  def base_attrs(overrides = {})
    {
      zip: "12345678",
      street: "Rua das Flores",
      number: "150",
      complement: "Apto 12",
      neighborhood: "Centro",
      city: "São Paulo",
      state: "SP",
      receiver_name: "Maria Receptora",
      receiver_cpf: "52998224725"
    }.merge(overrides)
  end

  def build_address(overrides = {})
    users(:confirmed).addresses.build(base_attrs(overrides))
  end

  test "a fully-populated record is valid" do
    address = build_address
    assert address.valid?, address.errors.full_messages.to_sentence
  end

  test "zip is required" do
    assert_not build_address(zip: nil).valid?
  end

  test "zip is normalized to 8 digits before validation" do
    address = build_address(zip: "12345-678")
    address.valid?
    assert_equal "12345678", address.zip
  end

  test "zip with fewer than 8 digits is rejected" do
    assert_not build_address(zip: "1234567").valid?
  end

  test "zip with more than 8 digits is rejected" do
    assert_not build_address(zip: "123456789").valid?
  end

  test "zip with only formatting characters normalizes to nil and fails presence" do
    address = build_address(zip: "----")
    assert_not address.valid?
    assert_nil address.zip
    assert_includes address.errors.attribute_names, :zip
  end

  test "street is required" do
    assert_not build_address(street: nil).valid?
  end

  test "number is required" do
    assert_not build_address(number: nil).valid?
  end

  test "number accepts letters alongside digits" do
    assert build_address(number: "448b").valid?
  end

  test "number accepts the Correios limit exactly" do
    assert build_address(number: "1" * Address::NUMBER_LIMIT).valid?
  end

  test "number longer than the Correios limit is rejected" do
    address = build_address(number: "1" * (Address::NUMBER_LIMIT + 1))
    assert_not address.valid?
    assert_includes address.errors.attribute_names, :number
  end

  test "a whole street line pasted into number is rejected instead of silently truncated" do
    address = build_address(number: "Rua Joel Jorge de Melo 105")
    assert_not address.valid?
    assert_includes address.errors.full_messages.to_sentence, "apenas o número"
  end

  test "neighborhood is required" do
    assert_not build_address(neighborhood: nil).valid?
  end

  test "city is required" do
    assert_not build_address(city: nil).valid?
  end

  test "complement is optional" do
    assert build_address(complement: nil).valid?
  end

  test "state is required" do
    assert_not build_address(state: nil).valid?
  end

  test "state must be a valid Brazilian UF" do
    assert_not build_address(state: "XX").valid?
    assert build_address(state: "RJ").valid?
  end

  test "receiver_name is required" do
    assert_not build_address(receiver_name: nil).valid?
  end

  test "receiver_cpf is required" do
    assert_not build_address(receiver_cpf: nil).valid?
  end

  test "receiver_cpf is normalized to digits before validation" do
    address = build_address(receiver_cpf: "529.982.247-25")
    address.valid?
    assert_equal "52998224725", address.receiver_cpf
  end

  test "receiver_cpf with only formatting characters normalizes to nil and fails presence" do
    address = build_address(receiver_cpf: "...-..")
    assert_not address.valid?
    assert_nil address.receiver_cpf
    assert_includes address.errors.attribute_names, :receiver_cpf
  end

  test "receiver_cpf with invalid mod-11 check digits is rejected" do
    assert_not build_address(receiver_cpf: "11111111111").valid?
  end

  test "the first address for a user is automatically default" do
    user = users(:confirmed)
    assert_empty user.addresses
    address = user.addresses.create!(base_attrs)
    assert address.default?
  end

  test "subsequent addresses are not default" do
    user = users(:confirmed)
    user.addresses.create!(base_attrs)
    second = user.addresses.create!(base_attrs(street: "Outra Rua"))
    assert_not second.default?
  end

  test "mark_default! flips the previous default off" do
    user = users(:confirmed)
    first = user.addresses.create!(base_attrs)
    second = user.addresses.create!(base_attrs(street: "Outra Rua"))
    second.mark_default!
    assert second.reload.default?
    assert_not first.reload.default?
  end

  test "mark_default! on the already-default address is a safe no-op" do
    user = users(:confirmed)
    address = user.addresses.create!(base_attrs)
    address.mark_default!
    assert address.reload.default?
  end

  test "default_first puts the default address ahead of the rest" do
    user = users(:confirmed)
    first = user.addresses.create!(base_attrs)
    second = user.addresses.create!(base_attrs(street: "Outra"))
    second.mark_default!
    assert_equal [ second.id, first.id ], user.addresses.default_first.pluck(:id)
  end

  test "destroying a user cascades to their addresses" do
    user = User.create!(
      email: "delete-me@example.com",
      password: "password123",
      password_confirmation: "password123",
      full_name: "Para Apagar",
      cpf: "52998224725",
      phone: "11988887777",
      confirmed_at: 1.day.ago
    )
    user.addresses.create!(base_attrs)
    assert_difference "Address.count", -1 do
      user.destroy!
    end
  end
end
