require "faraday"

module Correios
  module Api
    class PrePostagemStatus
      include Correios::Api::Client

      def self.fetch(codigo_objeto)
        new(codigo_objeto).fetch
      end

      def initialize(codigo_objeto)
        @codigo_objeto = codigo_objeto
      end

      def fetch
        response = request
        raise_for_status(response)
        Array(parse_body(response.body)["itens"]).first
      end

      private

      attr_reader :codigo_objeto

      def request
        connection.get("prepostagem/v2/prepostagens") do |req|
          req.params["codigoObjeto"] = codigo_objeto
          req.headers["Accept"] = "application/json"
          req.headers["Authorization"] = "Bearer #{Correios::Api.cartao_api_token}"
        end
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
        raise Correios::Api::TransientError, "pré-postagem status request failed: #{error.message}"
      end

      def parse_body(body)
        JSON.parse(body.to_s)
      rescue JSON::ParserError => error
        raise Correios::Api::Error, "unparseable pré-postagem status body: #{error.message}"
      end
    end
  end
end
