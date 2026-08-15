require "faraday"

module Correios
  module Api
    class DaceDownload
      include Correios::Api::Client

      PDF_TYPE = "C".freeze

      def self.fetch(pre_post_id)
        new(pre_post_id).fetch
      end

      def initialize(pre_post_id)
        @pre_post_id = pre_post_id
      end

      def fetch
        response = post
        raise_for_status(response)
        JSON.parse(response.body)
      end

      private

      attr_reader :pre_post_id

      # This endpoint reports a missing DACE through PPN codes in "msgs", where the
      # rótulo one uses "mensagem", so the message is lifted out before the shared
      # guard hands on a raw body nobody can read.
      def raise_for_status(response, ok: [ 200 ])
        return if ok.include?(response.status)

        message = messages_in(response)
        return super if message.blank?

        raise error_class_for(response), "DACE indisponível (pré-postagem #{pre_post_id}): #{message}"
      end

      def messages_in(response)
        Array(JSON.parse(response.body)["msgs"]).join(" ")
      rescue JSON::ParserError, TypeError
        ""
      end

      def error_class_for(response)
        status = response.status
        return Correios::Api::TransientError if status == 429 || status >= 500

        Correios::Api::Error
      end

      def post
        connection.post("prepostagem/v1/prepostagens/dce/dace/impressao") do |req|
          req.headers["Accept"] = "application/json"
          req.headers["Content-Type"] = "application/json"
          req.headers["Authorization"] = "Bearer #{Correios::Api.cartao_api_token}"
          req.body = { idsPrePostagens: [ pre_post_id ], tipoDace: PDF_TYPE }.to_json
        end
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
        raise Correios::Api::TransientError, "DACE download failed: #{error.message}"
      end
    end
  end
end
