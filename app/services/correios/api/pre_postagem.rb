require "faraday"

module Correios
  module Api
    class PrePostagem
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
        connection.post("prepostagem/v1/prepostagens") do |req|
          req.headers["Accept"] = "application/json"
          req.headers["Content-Type"] = "application/json"
          req.headers["Authorization"] = "Bearer #{Correios::Api.cartao_api_token}"
          req.body = payload.to_json
        end
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
        raise Correios::Api::TransientError, "pré-postagem request failed: #{error.message}"
      end
    end
  end
end
