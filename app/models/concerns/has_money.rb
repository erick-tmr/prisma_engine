module HasMoney
  def self.format(cents)
    "R$ %0.2f" % (cents.to_i / 100.0)
  end

  def self.parse(value)
    digits = value.to_s.gsub(/[^\d,]/, "").tr(",", ".")
    return 0 if digits.blank?

    (BigDecimal(digits) * 100).round
  end
end
