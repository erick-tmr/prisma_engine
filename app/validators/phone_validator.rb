class PhoneValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    digits = value.to_s.gsub(/\D/, "")
    return if digits.empty?

    record.errors.add(attribute, :invalid) unless Phones.national(digits)
  end
end
