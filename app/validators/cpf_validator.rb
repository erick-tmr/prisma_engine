# Validates a Brazilian CPF (Cadastro de Pessoas Físicas) via the official
# mod-11 algorithm. Stores nothing — the model normalizes the column elsewhere.
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

    check1 = mod11_digit(digits[0, 9], 10)
    check2 = mod11_digit(digits[0, 10], 11)
    digits[9].to_i == check1 && digits[10].to_i == check2
  end

  def mod11_digit(slice, start_weight)
    sum = slice.chars.each_with_index.sum { |c, i| c.to_i * (start_weight - i) }
    remainder = (sum * 10) % 11
    remainder == 10 ? 0 : remainder
  end
end
