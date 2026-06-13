class CartQuotesController < ApplicationController
  # Body copy for each ineligibility reason `Shipping::Quote` emits. Kept
  # alongside the controller so it's obvious which strings reach the user.
  INELIGIBLE_MESSAGES = {
    too_heavy:   "Não disponível para este pedido — provavelmente muitos jogos. " \
                 "O Mini Envios aceita pacotes de até 300g.",
    invalid_cep: "CEP não atendido por este serviço.",
    api_error:   "Erro temporário. Tente novamente em instantes.",
    unavailable: "Não disponível para este pedido."
  }.freeze

  UNEXPECTED_ERROR_MESSAGE =
    "Erro inesperado. Tente novamente em instantes ou entre em contato no WhatsApp."

  def create
    cep = normalize_cep(params[:cep])
    return render_error(:unprocessable_entity, "CEP inválido.") unless cep

    cart = ready_cart
    return render_error(:unprocessable_entity, "Seu carrinho está vazio.") unless cart

    render_quote_result(quote_response(cart, cep))
  rescue Correios::Api::InvalidObjectError
    render_error(:unprocessable_entity, "CEP inválido.")
  rescue Correios::Api::TransientError
    render_error(:service_unavailable, "Correios indisponível. Tente novamente em instantes.")
  rescue Correios::Api::Error
    # Auth/config errors (401, 403, malformed body) — the shopper can't fix
    # this. Surface a generic "unexpected" so they don't think their CEP is wrong.
    render_error(:service_unavailable, UNEXPECTED_ERROR_MESSAGE)
  end

  private

  # If at least one service is eligible, render the full list (the UI explains
  # any per-service ineligibilities inline). When every service failed, decide
  # the global message from the reason mix: a uniformly CEP-related failure
  # means the shopper typed a bad address; anything else is something they
  # can't fix and should call support about.
  def render_quote_result(response)
    services = response[:services]
    if services.any? { |service| service[:eligible] }
      render json: response
    elsif services.all? { |service| service[:reason] == :invalid_cep }
      render_error(:unprocessable_entity, "CEP inválido.")
    else
      render_error(:service_unavailable, UNEXPECTED_ERROR_MESSAGE)
    end
  end

  def ready_cart
    cart = current_cart
    cart.cleanup!
    cart.empty? ? nil : cart
  end

  def quote_response(cart, cep)
    weight_grams = Shipping::PackageWeight.call(cart)
    destination  = Shipping::CepLookup.call(cep)
    services     = Shipping::Quote.call(cep_destino: cep, weight_grams: weight_grams)
    {
      cep:         format_cep(cep),
      destination: { city: destination[:city], state: destination[:state] },
      services:    services.map { |service| serialize_service(service) }
    }
  end

  def normalize_cep(raw)
    digits = raw.to_s.gsub(/\D/, "")
    digits.length == 8 ? digits : nil
  end

  def format_cep(digits)
    "#{digits[0, 5]}-#{digits[5, 3]}"
  end

  def serialize_service(service)
    base = service.slice(:key, :label, :eligible, :reason)
    if service[:eligible]
      base.merge(service.slice(:price_cents, :price_formatted, :business_days))
    else
      base.merge(message: ineligible_message(service[:reason]))
    end
  end

  def ineligible_message(reason)
    INELIGIBLE_MESSAGES.fetch(reason, INELIGIBLE_MESSAGES[:unavailable])
  end

  def render_error(status, message)
    render status: status, json: { error: message }
  end
end
