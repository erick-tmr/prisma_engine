require "test_helper"

class OptionValueTest < ActiveSupport::TestCase
  test "name is unique within an option type" do
    dup = OptionValue.new(option_type: option_types(:idioma), name: "Inglês")
    assert_not dup.valid?
    assert_includes dup.errors[:name], "has already been taken"
  end

  test "same name is allowed across different option types" do
    ok = OptionValue.new(option_type: option_types(:caixa), name: "Inglês")
    assert ok.valid?
  end

  test "price contribution cannot be negative" do
    value = OptionValue.new(
      option_type: option_types(:caixa), name: "Negativa", price_contribution_cents: -1
    )
    assert_not value.valid?
  end
end
