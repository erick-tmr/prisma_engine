class CartQuotesController < ApplicationController
  # Body copy for each ineligibility reason `Shipping::Quote` emits. Kept
  # alongside the controller so it's obvious which strings reach the user.
  INELIGIBLE_MESSAGES = {
    too_heavy:   "Não disponível para este pedido — provavelmente muitos jogos. " \
                 "O Mini Envios aceita pacotes de até 300g.",
    unavailable: "Não disponível para este pedido."
  }.freeze

  def create
    cep = normalize_cep(params[:cep])
    return render_error(:unprocessable_entity, "CEP inválido.") unless cep

    cart = ready_cart
    return render_error(:unprocessable_entity, "Seu carrinho está vazio.") unless cart

    render json: quote_response(cart, cep)
  rescue Correios::Api::InvalidObjectError
    render_error(:unprocessable_entity, "CEP inválido.")
  rescue Correios::Api::TransientError
    render_error(:service_unavailable, "Correios indisponível. Tente novamente em instantes.")
  end

  private

  def ready_cart
    cart = current_cart
    cart.cleanup!
    cart.empty? ? nil : cart
  end

  def quote_response(cart, cep)
    weight_grams = package_weight_for(cart)
    destination  = Shipping::CepLookup.call(cep)
    services     = Shipping::Quote.call(cep_destino: cep, weight_grams: weight_grams)
    {
      cep:         format_cep(cep),
      destination: { city: destination[:city], state: destination[:state] },
      services:    services.map { |service| serialize_service(service) }
    }
  end

  def package_weight_for(cart)
    gotm          = GameOfTheMonth.current.first
    gotm_ids      = gotm ? gotm.products.pluck(:id).to_set : Set.new
    brindes_grams = gotm ? gotm.brindes.sum(:weight_grams) : 0
    cart.total_weight_grams(gotm_product_ids: gotm_ids, brindes_weight_grams: brindes_grams)
  end

  def normalize_cep(raw)
    digits = raw.to_s.gsub(/\D/, "")
    digits.length == 8 ? digits : nil
  end

  def format_cep(digits)
    "#{digits[0, 5]}-#{digits[5, 3]}"
  end

  def serialize_service(service)
    base = service.slice(:key, :label, :eligible)
    if service[:eligible]
      base.merge(service.slice(:price_cents, :price_formatted, :business_days))
    else
      base.merge(reason: service[:reason], message: ineligible_message(service[:reason]))
    end
  end

  def ineligible_message(reason)
    INELIGIBLE_MESSAGES.fetch(reason, INELIGIBLE_MESSAGES[:unavailable])
  end

  def render_error(status, message)
    render status: status, json: { error: message }
  end
end
