require "test_helper"

class UserTest < ActiveSupport::TestCase
  VALID_CPF = "11144477735"
  OTHER_VALID_CPF = "12345678909"

  def base_attrs(overrides = {})
    {
      email: "novo@example.com",
      password: "password123",
      password_confirmation: "password123",
      full_name: "Novo Cliente",
      cpf: VALID_CPF,
      phone: "11988887777"
    }.merge(overrides)
  end

  test "a fully-populated record is valid" do
    user = User.new(base_attrs(cpf: "52998224725"))
    assert user.valid?, user.errors.full_messages.to_sentence
  end

  test "full_name is required" do
    user = User.new(base_attrs(full_name: nil))
    assert_not user.valid?
    assert_includes user.errors.attribute_names, :full_name
  end

  test "cpf is required" do
    user = User.new(base_attrs(cpf: nil))
    assert_not user.valid?
    assert_includes user.errors.attribute_names, :cpf
  end

  test "cpf must be unique" do
    duplicate = User.new(base_attrs(cpf: users(:confirmed).cpf, email: "outro@example.com"))
    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :cpf
  end

  test "cpf with an invalid checksum is rejected" do
    user = User.new(base_attrs(cpf: "11144477700"))
    assert_not user.valid?
    assert_includes user.errors.attribute_names, :cpf
  end

  test "cpf is normalized to digits on validation" do
    user = User.new(base_attrs(cpf: "111.444.777-35"))
    user.valid?
    assert_equal "11144477735", user.cpf
  end

  test "cpf made of only formatting characters normalizes to nil" do
    user = User.new(base_attrs(cpf: "...-/"))
    assert_not user.valid?
    assert_nil user.cpf
    assert_includes user.errors.attribute_names, :cpf
  end

  test "phone is required" do
    user = User.new(base_attrs(phone: nil, cpf: "52998224725"))
    assert_not user.valid?
    assert_includes user.errors.attribute_names, :phone
  end

  test "phone over 20 characters is rejected" do
    user = User.new(base_attrs(phone: "1" * 21))
    assert_not user.valid?
    assert_includes user.errors.attribute_names, :phone
  end

  test "first_name returns the first whitespace-separated token" do
    assert_equal "Cliente", users(:confirmed).first_name
  end

  test "first_name returns the single token when full_name has no spaces" do
    user = users(:confirmed)
    user.full_name = "Madonna"
    assert_equal "Madonna", user.first_name
  end

  test "first_name returns nil when full_name is blank" do
    user = users(:confirmed)
    user.full_name = nil
    assert_nil user.first_name
  end

  test "default_address returns the address flagged default" do
    user = users(:confirmed)
    user.addresses.create!(
      zip: "12345678", street: "X", number: "1", neighborhood: "Y",
      city: "Z", state: "SP",
      receiver_name: "Maria", receiver_cpf: "52998224725"
    )
    second = user.addresses.create!(
      zip: "12345678", street: "Outra", number: "2", neighborhood: "Y",
      city: "Z", state: "SP",
      receiver_name: "Maria", receiver_cpf: "52998224725"
    )
    second.mark_default!
    assert_equal second, user.default_address
  end
end
