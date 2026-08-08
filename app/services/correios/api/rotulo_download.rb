require "faraday"

module Correios
  module Api
    class RotuloDownload
      include Correios::Api::Client

      LABEL_PENDING_CODE = "PPN-291".freeze
      LABEL_FAILED_CODES = %w[PPN-295 PPN-297].freeze

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
        return body if label_in?(body)

        message = Correios::Api::Payload.string(body, "mensagem").presence || response.body
        Rails.logger.warn("[RotuloDownload] recibo=#{recibo_id} sem etiqueta: #{message}")
        raise error_class_for(message), "rótulo download sem etiqueta (recibo #{recibo_id}): #{message}"
      end

      private

      attr_reader :recibo_id

      # A hollow 200 (both keys present, both null) is the same "no label yet" as
      # a body carrying a PPN code, so it takes the same classified path instead
      # of being handed on as a label with no bytes.
      def label_in?(body)
        %w[nome dados].all? { |key| Correios::Api::Payload.string(body, key).present? }
      end

      def error_class_for(message)
        text = message.to_s
        return Correios::Api::TransientError if text.include?(LABEL_PENDING_CODE)
        return Correios::Api::LabelGenerationFailedError if LABEL_FAILED_CODES.any? { |code| text.include?(code) }

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
