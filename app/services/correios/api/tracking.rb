require "faraday"

module Correios
  module Api
    class Tracking
      include Correios::Api::Client

      EPOCH = Time.at(0).utc

      def self.fetch(tracking_code)
        new(tracking_code).fetch
      end

      def initialize(tracking_code)
        @tracking_code = tracking_code
      end

      def fetch
        response = request
        raise_for_status(response)
        objeto = parse_objeto(response.body)
        eventos = Array(objeto["eventos"])
        raise_if_invalid(objeto) if eventos.empty?
        chronological(eventos.map { |evento| normalize(evento) })
      end

      private

      attr_reader :tracking_code

      def chronological(events)
        events.each_with_index
              .sort_by { |event, index| [ event[:occurred_at] || EPOCH, index ] }
              .map(&:first)
      end

      def request
        connection.get("srorastro/v1/objetos/#{tracking_code}") do |req|
          req.params["resultado"] = "T"
          req.headers["Accept"] = "application/json"
          req.headers["Authorization"] = "Bearer #{Correios::Api.api_token}"
        end
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
        raise Correios::Api::TransientError, "rastro request failed: #{error.message}"
      end

      def parse_objeto(body)
        JSON.parse(body.presence || "{}").dig("objetos", 0) || {}
      rescue JSON::ParserError => error
        raise Correios::Api::Error, "unparseable rastro body: #{error.message}"
      end

      def raise_if_invalid(objeto)
        message = objeto["mensagem"].to_s
        return unless message.match?(/\bSRO-019\b/i)

        raise Correios::Api::InvalidObjectError, message
      end

      def normalize(evento)
        {
          code: evento["codigo"],
          type: evento["tipo"],
          description: evento["descricao"].presence,
          occurred_at: Correios::Api::Timestamp.parse(evento["dtHrCriado"]),
          payload: evento
        }
      end
    end
  end
end
