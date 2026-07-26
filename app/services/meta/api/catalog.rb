require "faraday"

module Meta
  module Api
    class Catalog
      include Meta::Api::Client

      def self.batch(requests)
        new(requests).batch
      end

      def initialize(requests)
        @requests = requests
      end

      def batch
        response = post
        raise_for_status(response)
        parse(response.body)
      end

      private

      attr_reader :requests

      def post
        connection.post(path) do |req|
          req.headers["Accept"]        = "application/json"
          req.headers["Content-Type"]  = "application/json"
          req.headers["Authorization"] = "Bearer #{Meta::Api.access_token}"
          req.body = { item_type: "PRODUCT_ITEM", allow_upsert: true, requests: requests }.to_json
        end
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
        raise Meta::Api::TransientError, "meta items_batch request failed: #{error.message}"
      end

      def path
        "#{Meta::Api::API_VERSION}/#{Meta::Api.catalog_id}/items_batch"
      end

      def parse(raw)
        JSON.parse(raw.presence || "{}")
      rescue JSON::ParserError => error
        raise Meta::Api::PermanentError, "unparseable meta body: #{error.message}"
      end
    end
  end
end
