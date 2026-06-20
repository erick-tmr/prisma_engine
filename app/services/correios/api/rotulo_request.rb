require "faraday"

module Correios
  module Api
    class RotuloRequest
      include Correios::Api::Client

      def self.create(payload)
        new(payload).create
      end

      def initialize(payload)
        @payload = payload
      end

      def create
        response = post
        raise_for_status(response, ok: [ 200, 201 ])
        JSON.parse(response.body)
      end

      private

      attr_reader :payload

      def post
        connection.post("prepostagem/v1/prepostagens/rotulo/assincrono/pdf") do |req|
          req.headers["Accept"] = "application/json"
          req.headers["Content-Type"] = "application/json"
          req.headers["Authorization"] = "Bearer #{ENV['CORREIOS_CARTAO_API_TOKEN']}"
          req.body = payload.to_json
        end
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
        raise Correios::Api::TransientError, "rótulo request failed: #{error.message}"
      end
    end
  end
end
