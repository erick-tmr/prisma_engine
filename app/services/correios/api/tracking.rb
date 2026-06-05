require "faraday"

module Correios
  module Api
    # Reads the Correios rastro (tracking) API. Our contract has no webhooks, so a
    # scheduled job polls this per shipment (see SyncShipmentJob).
    #
    #   GET {base}/srorastro/v1/objetos/{code}?resultado=T
    #   Authorization: Bearer <CORREIOS_API_TOKEN>
    #
    # The token is supplied and rotated out of band — we don't run the autentica
    # exchange. We hand events back oldest-first, sorted by their own timestamp
    # (dtHrCriado), so a stable `position` can index them and `.last` is the latest.
    class Tracking
      include Correios::Api::Client

      EPOCH = Time.at(0).utc # sort key for an event missing a timestamp

      def self.fetch(tracking_code)
        new(tracking_code).fetch
      end

      def initialize(tracking_code)
        @tracking_code = tracking_code
      end

      # Normalized events, oldest-first by event time. The full raw evento stays under
      # :payload so nothing the API sends is lost. A 200 can also carry no events and
      # just a `mensagem`: SRO-020 (not in Correios' base yet) is benign — we return []
      # and keep polling; SRO-019 (invalid object) is permanent — we raise so the
      # caller can stop and flag it.
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

      # Oldest-first by dtHrCriado, rather than trusting the response's array order;
      # the original index breaks ties so `position` stays stable across polls.
      def chronological(events)
        events.each_with_index
              .sort_by { |event, index| [ event[:occurred_at] || EPOCH, index ] }
              .map(&:first)
      end

      def request
        connection.get("srorastro/v1/objetos/#{tracking_code}") do |req|
          req.params["resultado"] = "T"
          req.headers["Accept"] = "application/json"
          req.headers["Authorization"] = "Bearer #{ENV['CORREIOS_API_TOKEN']}"
        end
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
        raise Correios::Api::TransientError, "rastro request failed: #{error.message}"
      end

      def parse_objeto(body)
        JSON.parse(body.presence || "{}").dig("objetos", 0) || {}
      rescue JSON::ParserError => error
        raise Correios::Api::Error, "unparseable rastro body: #{error.message}"
      end

      # SRO-019 = "objeto inválido": the code is malformed/unknown and will never
      # yield events. Other no-event messages (e.g. SRO-020) just mean "not yet".
      def raise_if_invalid(objeto)
        message = objeto["mensagem"].to_s
        return unless message.match?(/\bSRO-019\b/i)

        raise Correios::Api::InvalidObjectError, message
      end

      # Translate the vendor's Portuguese wire fields into our domain vocabulary:
      # codigo → code, tipo → type. The raw evento stays under :payload.
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
