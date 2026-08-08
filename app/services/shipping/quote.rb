module Shipping
  class Quote
    CACHE_TTL = 5.minutes

    def self.call(cep_destino:, weight_grams:)
      new(cep_destino: cep_destino, weight_grams: weight_grams).call
    end

    def initialize(cep_destino:, weight_grams:)
      @cep_destino  = cep_destino
      @weight_grams = weight_grams
    end

    def call
      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) { fetch_services }
    end

    private

    attr_reader :cep_destino, :weight_grams

    def cache_key
      "correios:quote:#{cep_destino}:#{weight_grams}"
    end

    def fetch_services
      preco_rows = Correios::Api::Preco.fetch(
        cep_origem:    Shipping::ORIGIN_CEP,
        cep_destino:   cep_destino,
        weight_grams:  weight_grams,
        service_codes: Shipping::SERVICES.values
      ).index_by { |row| Correios::Api::Payload.string(row, "nuRequisicao") }

      prazo_rows = Correios::Api::Prazo.fetch(
        cep_origem:    Shipping::ORIGIN_CEP,
        cep_destino:   cep_destino,
        service_codes: Shipping::SERVICES.values
      ).index_by { |row| Correios::Api::Payload.string(row, "nuRequisicao") }

      Shipping::SERVICES.map do |key, code|
        build_service(key, code, preco_rows[code], prazo_rows[code])
      end
    end

    def build_service(key, code, preco, prazo)
      common = { key: key, label: Shipping.service_label(key) }
      tx_erro = Correios::Api::Payload.string(preco, "txErro").presence
      return common.merge(eligible: false, reason: classify_error(tx_erro)) if tx_erro
      return common.merge(eligible: false, reason: ineligibility_reason(key)) unless eligible?(code, preco, prazo)

      price_cents = quoted_price_cents(preco)
      # A row that quotes no price is not a free delivery: without this the
      # customer would be charged the handling fee alone for a real shipment.
      return common.merge(eligible: false, reason: :api_error) if price_cents.nil?

      common.merge(
        eligible: true, price_cents: price_cents, price_formatted: HasMoney.format(price_cents),
        business_days: Correios::Api::Payload.integer(prazo, "prazoEntrega").to_i
      )
    end

    def eligible?(requested_code, preco, prazo)
      return false unless preco && prazo

      reader = Correios::Api::Payload
      reader.string(preco, "coProduto") == requested_code && reader.string(prazo, "coProduto") == requested_code
    end

    def quoted_price_cents(preco)
      price = Correios::Api::Payload.decimal(preco, "pcFinal")
      return if price.nil? || !price.positive?

      (price * 100).round + handling_fee_cents
    end

    # :reek:ControlParameter
    def ineligibility_reason(key)
      key == :mini_envios ? :too_heavy : :unavailable
    end

    # :reek:ControlParameter
    def classify_error(tx_erro)
      tx_erro.match?(/CEP/i) ? :invalid_cep : :api_error
    end

    def handling_fee_cents
      @handling_fee_cents ||= StoreSetting.current.handling_fee_cents
    end
  end
end
