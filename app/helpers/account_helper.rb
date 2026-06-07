module AccountHelper
  ORDER_STATUS_BADGE_CLASSES = {
    "entregue" => "text-bg-success",
    "enviado" => "text-bg-success",
    "etiqueta_emitida" => "text-bg-primary",
    "em_producao" => "text-bg-primary",
    "pagamento_confirmado" => "text-bg-primary",
    "aguardando_pagamento" => "text-bg-warning",
    "aguardando_componentes" => "text-bg-warning",
    "problema_na_producao" => "text-bg-danger"
  }.freeze

  ORDER_PAYMENT_METHOD_LABELS = {
    pix: "Pix",
    infinite_pay_card: "InfinitePay (cartão)"
  }.freeze

  def account_section_active?(section_path)
    request.path == section_path || request.path.start_with?("#{section_path}/")
  end

  def number_to_cep(digits)
    digits = digits.to_s
    return digits unless digits.match?(/\A\d{8}\z/)

    "#{digits[0, 5]}-#{digits[5, 3]}"
  end

  def format_brl(cents)
    "R$ #{format('%.2f', cents.to_i / 100.0).tr('.', ',')}"
  end

  def order_status_badge_class(status)
    ORDER_STATUS_BADGE_CLASSES.fetch(status.to_s, "text-bg-secondary")
  end

  def order_payment_method_label(method)
    ORDER_PAYMENT_METHOD_LABELS.fetch(method, method.to_s.humanize)
  end
end
