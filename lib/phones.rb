module Phones
  module_function

  def e164(raw)
    digits = raw.to_s.gsub(/\D/, "")
    return if digits.empty?

    digits = "55#{digits}" unless digits.start_with?("55") && digits.size >= 12
    "+#{digits}"
  end
end
