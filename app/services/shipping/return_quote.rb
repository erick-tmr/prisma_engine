module Shipping
  class ReturnQuote
    CACHE_TTL = 5.minutes

    def self.call(shipment)
      new(zip: shipment.zip, weight_grams: shipment.weight_grams).call
    end

    def self.price_cents(shipment, service)
      call(shipment)[service.to_s.to_sym]
    end

    def initialize(zip:, weight_grams:)
      @zip = zip
      @weight_grams = weight_grams
    end

    def call
      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) { fetch_prices }
    end

    private

    attr_reader :zip, :weight_grams

    def cache_key
      "correios:return_quote:#{zip}:#{Shipping::ORIGIN_CEP}:#{weight_grams}"
    end

    def fetch_prices
      rows = Correios::Api::Preco.fetch(
        cep_origem:    zip,
        cep_destino:   Shipping::ORIGIN_CEP,
        weight_grams:  weight_grams,
        service_codes: Shipping::SERVICES.values
      ).select { |row| quoted_as_requested?(row) }.index_by { |row| reader.string(row, "nuRequisicao") }

      Shipping::SERVICES.to_h { |key, code| [ key, rows[code] && Shipping::Quote.correios_cents(rows[code]) ] }
    end

    def quoted_as_requested?(row)
      reader.string(row, "txErro").empty? && reader.string(row, "coProduto") == reader.string(row, "nuRequisicao")
    end

    def reader
      Correios::Api::Payload
    end
  end
end
