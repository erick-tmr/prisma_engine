class CpfValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    digits = value.to_s.gsub(/\D/, "")
    return if digits.empty?
    record.errors.add(attribute, :invalid) unless valid_cpf?(digits)
  end

  private

  def valid_cpf?(digits)
    return false unless digits.length == 11
    return false if digits.chars.uniq.size == 1

    first_check = mod11_digit(digits[0, 9], 10)
    second_check = mod11_digit(digits[0, 10], 11)
    digits[9].to_i == first_check && digits[10].to_i == second_check
  end

  def mod11_digit(slice, start_weight)
    sum = slice.chars.each_with_index.sum { |char, position| char.to_i * (start_weight - position) }
    remainder = (sum * 10) % 11
    remainder == 10 ? 0 : remainder
  end
end
