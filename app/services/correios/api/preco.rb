require "faraday"

module Correios
  module Api
    # Queries the Correios pricing endpoint for one or more service codes in a
    # single batched POST.
    #
    #   POST {base}/preco/v1/nacional
    #   Authorization: Bearer <CORREIOS_CARTAO_API_TOKEN>
    #
    # Returns the parsed JSON Array exactly as Correios sends it. Mapping
    # (price parsing, eligibility check by coProduto, currency formatting)
    # happens in Shipping::Quote.
    #
    # The vendor swaps `coProduto` in the response when a requested service
    # isn't eligible for the given package — e.g. Mini Envios (04227) over
    # 300g comes back as 04960. The domain layer compares request vs response
    # codes to surface that as a domain-level "ineligible" flag.
    class Preco
      include Correios::Api::Client

      # :reek:LongParameterList — keyword args document the request shape directly;
      # bundling them into a Value Object would add indirection without clarity.
      def self.fetch(cep_origem:, cep_destino:, weight_grams:, service_codes:)
        new(cep_origem: cep_origem,
            cep_destino: cep_destino,
            weight_grams: weight_grams,
            service_codes: service_codes).fetch
      end

      def initialize(cep_origem:, cep_destino:, weight_grams:, service_codes:)
        @cep_origem    = cep_origem
        @cep_destino   = cep_destino
        @weight_grams  = weight_grams
        @service_codes = service_codes
      end

      def fetch
        response = post
        # 429 stays a TransientError (handled by raise_for_status); other 4xx
        # are permanent "Correios rejected this CEP / weight / payload" cases.
        if response.status.between?(400, 499) && response.status != 429
          raise Correios::Api::InvalidObjectError, "preco rejected: #{response.body}"
        end
        raise_for_status(response)
        parse(response.body)
      end

      private

      attr_reader :cep_origem, :cep_destino, :weight_grams, :service_codes

      def post
        connection.post("preco/v1/nacional") do |req|
          req.headers["Accept"]        = "application/json"
          req.headers["Content-Type"]  = "application/json"
          req.headers["Authorization"] = "Bearer #{ENV['CORREIOS_CARTAO_API_TOKEN']}"
          req.body = body.to_json
        end
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
        raise Correios::Api::TransientError, "preco request failed: #{error.message}"
      end

      def body
        dimensions = Shipping::PACKAGE_DIMENSIONS
        {
          idLote: "1",
          parametrosProduto: service_codes.map do |code|
            {
              nuRequisicao: code,
              coProduto:    code,
              cepOrigem:    cep_origem,
              cepDestino:   cep_destino,
              psObjeto:     weight_grams.to_s,
              tpObjeto:     "2",
              comprimento:  dimensions[:comprimento_cm].to_s,
              largura:      dimensions[:largura_cm].to_s,
              altura:       dimensions[:altura_cm].to_s,
              dtEvento:     Date.current.strftime("%d/%m/%Y")
            }
          end
        }
      end

      def parse(raw)
        Array(JSON.parse(raw.presence || "[]"))
      rescue JSON::ParserError => error
        raise Correios::Api::Error, "unparseable preco body: #{error.message}"
      end
    end
  end
end
