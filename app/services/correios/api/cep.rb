require "faraday"

module Correios
  module Api
    # Reads the Correios CEP v2 lookup API. Fed by the address form when the
    # customer finishes typing a CEP; we hand the parsed body back and let the
    # domain layer translate it into our Address columns.
    #
    #   GET {base}/cep/v2/enderecos/{cep}
    #   Authorization: Bearer <correios.api_token>
    #
    # The same Bearer token used for rastro: Correios issues one credential per
    # contract that gates every read endpoint we use today.
    class Cep
      include Correios::Api::Client

      def self.find(cep)
        new(cep).find
      end

      def initialize(cep)
        @cep = cep
      end

      # Returns the parsed JSON Hash exactly as Correios sends it (the response
      # shape varies: a street-specific CEP carries logradouro + bairro, a
      # town-wide one only localidade + localidadeSuperior). Mapping happens in
      # Shipping::CepLookup, not here.
      def find
        response = request
        # 404 means the CEP doesn't exist in Correios' base: permanent, not a
        # transient blip, so the caller can stop instead of retrying.
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
