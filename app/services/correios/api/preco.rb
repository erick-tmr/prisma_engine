require "faraday"

module Correios
  module Api
    class Preco
      include Correios::Api::Client

      PERMANENT_REJECTIONS = [ 400, 422 ].freeze

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
        if PERMANENT_REJECTIONS.include?(response.status)
          raise Correios::Api::InvalidObjectError, "preco rejected: #{response.body}"
        end
        raise_for_status(response, ok: [ 200, 206 ])
        parse(response.body)
      end

      private

      attr_reader :cep_origem, :cep_destino, :weight_grams, :service_codes

      def post
        connection.post("preco/v1/nacional") do |req|
          req.headers["Accept"]        = "application/json"
          req.headers["Content-Type"]  = "application/json"
          req.headers["Authorization"] = "Bearer #{Correios::Api.api_token}"
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
