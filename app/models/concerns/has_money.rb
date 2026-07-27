module HasMoney
  def self.format(cents)
    ActiveSupport::NumberHelper.number_to_currency(
      cents.to_i / 100.0, unit: "R$ ", separator: ",", delimiter: ".", format: "%u%n"
    )
  end

  def self.parse(value)
    digits = value.to_s.gsub(/[^\d,]/, "").tr(",", ".")
    return 0 if digits.blank?

    (BigDecimal(digits) * 100).round
  end
end
