require "faraday"

module Correios
  module Api
    class Cep
      include Correios::Api::Client

      def self.find(cep)
        new(cep).find
      end

      def initialize(cep)
        @cep = cep
      end

      def find
        response = request
        raise Correios::Api::InvalidObjectError, "CEP #{cep} not found" if response.status == 404
        raise_for_status(response)
        parse(response.body)
      end

      private

      attr_reader :cep

      def request
        connection.get("cep/v2/enderecos/#{cep}") do |req|
          req.headers["Accept"] = "application/json"
          req.headers["Authorization"] = "Bearer #{Correios::Api.api_token}"
        end
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
        raise Correios::Api::TransientError, "cep request failed: #{error.message}"
      end

      def parse(body)
        JSON.parse(body.presence || "{}")
      rescue JSON::ParserError => error
        raise Correios::Api::Error, "unparseable cep body: #{error.message}"
      end
    end
  end
end
