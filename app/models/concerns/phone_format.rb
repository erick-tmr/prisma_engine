module PhoneFormat
  def self.call(digits)
    digits.to_s
          .gsub(/\A(\d{2})(\d{5})(\d{4})\z/, '(\1) \2-\3')
          .gsub(/\A(\d{2})(\d{4})(\d{4})\z/, '(\1) \2-\3')
  end
end
