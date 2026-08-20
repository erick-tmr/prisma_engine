module Phones
  COUNTRY_CODE = "55".freeze
  AREA_CODE = /\A[1-9][1-9]\z/
  LANDLINE_DIGITS = 10
  MOBILE_DIGITS = 11
  WHATSAPP_CHAT_URL = "https://web.whatsapp.com/send".freeze

  module_function

  def national(raw)
    digits = drop_country_code(raw.to_s.gsub(/\D/, ""))
    digits if brazilian?(digits)
  end

  def e164(raw)
    digits = national(raw)
    "+#{COUNTRY_CODE}#{digits}" if digits
  end

  def whatsapp_url(raw)
    digits = national(raw)
    "#{WHATSAPP_CHAT_URL}?phone=#{COUNTRY_CODE}#{digits}" if digits&.length == MOBILE_DIGITS
  end

  def drop_country_code(digits)
    digits.length > MOBILE_DIGITS ? digits.delete_prefix(COUNTRY_CODE) : digits
  end

  def brazilian?(digits)
    return false unless [ LANDLINE_DIGITS, MOBILE_DIGITS ].include?(digits.length)
    return false unless digits[0, 2].match?(AREA_CODE)

    digits.length == LANDLINE_DIGITS || digits[2] == "9"
  end
end
