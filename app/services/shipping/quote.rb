module Shipping
  # Live cart shipping quote — one batched preço call + one batched prazo
  # call, eligibility filtered, results cached for 5 minutes.
  #
  #   Shipping::Quote.call(cep_destino: "01310100", weight_grams: 150)
  #   → [
  #       { key: :sedex,       label: "SEDEX",      eligible: true,
  #         price_cents: 1984, price_formatted: "R$ 19.84", business_days: 2 },
  #       { key: :pac,         label: "PAC",        eligible: true,
  #         price_cents: 2890, price_formatted: "R$ 28.90", business_days: 7 },
  #       { key: :mini_envios, label: "Mini Envios", eligible: false, reason: :too_heavy }
  #     ]
  #
  # Eligibility rule: Correios swaps `coProduto` in the price response when a
  # requested service isn't valid for the package (e.g. Mini Envios > 300g
  # comes back as 04960). We compare requested code vs response code; on a
  # mismatch the service is reported as ineligible with a `reason` so the UI
  # can surface a friendly explanation.
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

    # :reek:LongParameterList — local plumbing; the four bits are the per-service
    # inputs we need to produce one service row.
    def build_service(key, code, preco, prazo)
      common = { key: key, label: SERVICE_LABELS.fetch(key) }
      tx_erro = preco && preco["txErro"]
      # Correios returns 200 with a per-row txErro field when the request was
      # accepted but the service itself can't be priced (bad CEP, coverage
      # gaps, vendor errors). Bucket those so the controller can dispatch
      # "all services failed for CEP" → 422 vs "something else" → 503.
      return common.merge(eligible: false, reason: classify_error(tx_erro)) if tx_erro

      if eligible?(code, preco, prazo)
        common.merge(
          eligible:        true,
          price_cents:     parse_price_cents(preco["pcFinal"]),
          price_formatted: HasMoney.format(parse_price_cents(preco["pcFinal"])),
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

    # :reek:ControlParameter — the method exists exactly to branch on the key.
    def ineligibility_reason(key)
      key == :mini_envios ? :too_heavy : :unavailable
    end

    # CEP-related txErro phrases ("CEP inexistente", "CEP inválido") all carry
    # the substring "CEP". Anything else is an API-level issue the shopper
    # can't fix from the cart, so we tag it for the "unexpected error" path.
    # :reek:ControlParameter — the method exists exactly to branch on the message.
    def classify_error(tx_erro)
      tx_erro.match?(/CEP/i) ? :invalid_cep : :api_error
    end

    # Correios returns BR-decimal strings like "19,84". Convert to integer
    # cents for the rest of the app (HasMoney works in cents).
    def parse_price_cents(raw)
      (raw.to_s.tr(",", ".").to_f * 100).round
    end
  end
end
