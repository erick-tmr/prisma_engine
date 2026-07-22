module Shipping
  class Quote
    SERVICE_LABELS = {
      sedex:       "SEDEX",
      pac:         "PAC",
      mini_envios: "Mini Envios"
    }.freeze

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
      ).index_by { |row| row["nuRequisicao"] }

      prazo_rows = Correios::Api::Prazo.fetch(
        cep_origem:    Shipping::ORIGIN_CEP,
        cep_destino:   cep_destino,
        service_codes: Shipping::SERVICES.values
      ).index_by { |row| row["nuRequisicao"] }

      Shipping::SERVICES.map do |key, code|
        build_service(key, code, preco_rows[code], prazo_rows[code])
      end
    end

    def build_service(key, code, preco, prazo)
      common = { key: key, label: SERVICE_LABELS.fetch(key) }
      tx_erro = preco && preco["txErro"]
      return common.merge(eligible: false, reason: classify_error(tx_erro)) if tx_erro

      if eligible?(code, preco, prazo)
        price_cents = parse_price_cents(preco["pcFinal"]) + handling_fee_cents
        common.merge(
          eligible:        true,
          price_cents:     price_cents,
          price_formatted: HasMoney.format(price_cents),
          business_days:   prazo["prazoEntrega"].to_i
        )
      else
        common.merge(eligible: false, reason: ineligibility_reason(key))
      end
    end

    def eligible?(requested_code, preco, prazo)
      return false unless preco && prazo
      preco["coProduto"] == requested_code && prazo["coProduto"] == requested_code
    end

    # :reek:ControlParameter (the method exists exactly to branch on the key)
    def ineligibility_reason(key)
      key == :mini_envios ? :too_heavy : :unavailable
    end

    # :reek:ControlParameter (the method exists exactly to branch on the message)
    def classify_error(tx_erro)
      tx_erro.match?(/CEP/i) ? :invalid_cep : :api_error
    end

    def parse_price_cents(raw)
      (raw.to_s.tr(",", ".").to_f * 100).round
    end

    def handling_fee_cents
      @handling_fee_cents ||= StoreSetting.current.handling_fee_cents
    end
  end
end
