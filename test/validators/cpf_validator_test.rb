require "test_helper"

class CpfValidatorTest < ActiveSupport::TestCase
  # A bare ActiveModel host so the validator can be exercised independently of
  # the User record (which adds its own normalization + uniqueness branches).
  class Holder
    include ActiveModel::Validations
    attr_accessor :cpf
    validates :cpf, cpf: true
  end

  def holder(value)
    Holder.new.tap { |h| h.cpf = value }
  end

  test "accepts a valid digits-only CPF" do
    assert holder("11144477735").valid?
  end

  test "accepts a valid CPF with the canonical dotted formatting" do
    assert holder("111.444.777-35").valid?
  end

  test "accepts the second-digit-zero edge case (12345678909)" do
    # exercises the `remainder == 10 ? 0 : remainder` branch
    assert holder("12345678909").valid?
  end

  test "rejects an invalid checksum" do
    assert_not holder("11144477730").valid?
  end

  test "rejects a CPF whose digits are all identical" do
    assert_not holder("11111111111").valid?
  end

  test "rejects a CPF shorter than 11 digits" do
    assert_not holder("1234567890").valid?
  end

  test "rejects a CPF longer than 11 digits" do
    assert_not holder("123456789012").valid?
  end

  test "passes when the value is nil (presence handled elsewhere)" do
    assert holder(nil).valid?
  end

  test "passes when the value is blank after stripping non-digits" do
    assert holder("---").valid?
  end
end
