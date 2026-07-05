module HasMoney
  def self.format(cents)
    "R$ %0.2f" % (cents.to_i / 100.0)
  end

  # Parses a pt-BR money string ("1.234,50", "190,00", "20") into integer cents.
  # Blank or unparseable input is zero — the catalog's "Sob consulta" sentinel.
  def self.parse(value)
    digits = value.to_s.gsub(/[^\d,]/, "").tr(",", ".")
    return 0 if digits.blank?

    (BigDecimal(digits) * 100).round
  end
end
