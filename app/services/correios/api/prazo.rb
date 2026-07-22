require "faraday"

module Correios
  module Api
    class Prazo
      include Correios::Api::Client

      PERMANENT_REJECTIONS = [ 400, 422 ].freeze

      def self.fetch(cep_origem:, cep_destino:, service_codes:)
        new(cep_origem: cep_origem, cep_destino: cep_destino, service_codes: service_codes).fetch
      end

      def initialize(cep_origem:, cep_destino:, service_codes:)
        @cep_origem    = cep_origem
        @cep_destino   = cep_destino
        @service_codes = service_codes
      end

      def fetch
        response = post
        if PERMANENT_REJECTIONS.include?(response.status)
          raise Correios::Api::InvalidObjectError, "prazo rejected: #{response.body}"
        end
        raise_for_status(response, ok: [ 200, 206 ])
        parse(response.body)
      end

      private

      attr_reader :cep_origem, :cep_destino, :service_codes

      def post
        connection.post("prazo/v1/nacional") do |req|
          req.headers["Accept"]        = "application/json"
          req.headers["Content-Type"]  = "application/json"
          req.headers["Authorization"] = "Bearer #{Correios::Api.api_token}"
          req.body = body.to_json
        end
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
        raise Correios::Api::TransientError, "prazo request failed: #{error.message}"
      end

      def body
        {
          idLote: "1",
          parametrosPrazo: service_codes.map do |code|
            {
              coProduto:    code,
              nuRequisicao: code,
              dtEvento:     Date.current.strftime("%d/%m/%Y"),
              cepOrigem:    cep_origem,
              cepDestino:   cep_destino
            }
          end
        }
      end

      def parse(raw)
        Array(JSON.parse(raw.presence || "[]"))
      rescue JSON::ParserError => error
        raise Correios::Api::Error, "unparseable prazo body: #{error.message}"
      end
    end
  end
end
