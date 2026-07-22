module AccountHelper
  ORDER_PAYMENT_METHOD_LABELS = {
    "pix" => "Pix",
    "credit_card" => "Cartão de crédito"
  }.freeze

  ORDER_PAYMENT_METHOD_ICONS = {
    "pix" => "bi-cash-coin",
    "credit_card" => "bi-credit-card"
  }.freeze

  ORDER_PAYMENT_STATUS_ICONS = {
    paid: "bi-check-circle-fill",
    pending: "bi-hourglass-split"
  }.freeze

  def account_section_active?(section_path)
    request.path == section_path || request.path.start_with?("#{section_path}/")
  end

  def number_to_cep(digits)
    digits = digits.to_s
    return digits unless digits.match?(/\A\d{8}\z/)

    "#{digits[0, 5]}-#{digits[5, 3]}"
  end

  def format_cpf(digits)
    digits = digits.to_s
    return digits unless digits.match?(/\A\d{11}\z/)

    "#{digits[0, 3]}.#{digits[3, 3]}.#{digits[6, 3]}-#{digits[9, 2]}"
  end

  # First letter of the first whitespace-separated token + first letter of the
  # last token (or just the first token's initial if the name is a single word).
  # Drives the rainbow avatar chip in the account header.
  def account_avatar_initials(name)
    tokens = name.to_s.split(/\s+/).reject(&:empty?)
    return "" if tokens.empty?

    initials = tokens.first[0]
    initials += tokens.last[0] if tokens.size > 1
    initials.upcase
  end

  def format_brl(cents)
    "R$ #{format('%.2f', cents.to_i / 100.0).tr('.', ',')}"
  end

  def order_payment_method_label(method)
    return t("account.orders.show.payment_method_pending") if method.blank?

    ORDER_PAYMENT_METHOD_LABELS.fetch(method.to_s, method.to_s.humanize)
  end

  def order_payment_method_icon(method)
    ORDER_PAYMENT_METHOD_ICONS.fetch(method.to_s, "bi-wallet2")
  end

  def order_payment_status_icon(status)
    ORDER_PAYMENT_STATUS_ICONS.fetch(status.to_sym, "bi-hourglass-split")
  end
end
