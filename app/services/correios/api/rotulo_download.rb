require "faraday"

module Correios
  module Api
    class RotuloDownload
      include Correios::Api::Client

      def self.fetch(recibo_id)
        new(recibo_id).fetch
      end

      def initialize(recibo_id)
        @recibo_id = recibo_id
      end

      def fetch
        response = get
        raise_for_status(response)
        JSON.parse(response.body)
      end

      private

      attr_reader :recibo_id

      def get
        connection.get("prepostagem/v1/prepostagens/rotulo/download/assincrono/#{recibo_id}") do |req|
          req.headers["Accept"] = "application/json"
          req.headers["Authorization"] = "Bearer #{ENV['CORREIOS_CARTAO_API_TOKEN']}"
        end
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
        raise Correios::Api::TransientError, "rótulo download failed: #{error.message}"
      end
    end
  end
end
