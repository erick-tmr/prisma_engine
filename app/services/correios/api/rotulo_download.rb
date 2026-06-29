require "faraday"

module Correios
  module Api
    class RotuloDownload
      include Correios::Api::Client

      LABEL_PENDING_CODE = "PPN-291".freeze
      LABEL_FAILED_CODE = "PPN-295".freeze

      def self.fetch(recibo_id)
        new(recibo_id).fetch
      end

      def initialize(recibo_id)
        @recibo_id = recibo_id
      end

      def fetch
        response = get
        raise_for_status(response)
        body = JSON.parse(response.body)
        return body if body.is_a?(Hash) && body.key?("nome") && body.key?("dados")

        message = body.is_a?(Hash) ? body["mensagem"] : response.body
        Rails.logger.warn("[RotuloDownload] recibo=#{recibo_id} sem etiqueta: #{message}")
        raise error_class_for(message), "rótulo download sem etiqueta (recibo #{recibo_id}): #{message}"
      end

      private

      attr_reader :recibo_id

      def error_class_for(message)
        text = message.to_s
        return Correios::Api::TransientError if text.include?(LABEL_PENDING_CODE)
        return Correios::Api::LabelGenerationFailedError if text.include?(LABEL_FAILED_CODE)

        Correios::Api::Error
      end

      def get
        connection.get("prepostagem/v1/prepostagens/rotulo/download/assincrono/#{recibo_id}") do |req|
          req.headers["Accept"] = "application/json"
          req.headers["Authorization"] = "Bearer #{Correios::Api.cartao_api_token}"
        end
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
        raise Correios::Api::TransientError, "rótulo download failed: #{error.message}"
      end
    end
  end
end
