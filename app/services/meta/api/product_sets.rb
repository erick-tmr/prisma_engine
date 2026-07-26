require "faraday"

module Meta
  module Api
    class ProductSets
      include Meta::Api::Client

      def self.list
        new.list
      end

      def self.create(name:, filter:, shop_id:)
        new.create(name: name, filter: filter, shop_id: shop_id)
      end

      def self.update(id, filter:)
        new.update(id, filter: filter)
      end

      def list
        response = request(:get, sets_path) { |req| req.params["fields"] = "name" }
        parse(response.body).fetch("data", [])
      end

      def create(name:, filter:, shop_id:)
        response = request(:post, sets_path) do |req|
          req.params["name"] = name
          req.params["filter"] = filter.to_json
          req.params["publish_to_shops"] = [ shop_id ].to_json
        end
        parse(response.body)
      end

      def update(id, filter:)
        response = request(:post, "#{Meta::Api::API_VERSION}/#{id}") { |req| req.params["filter"] = filter.to_json }
        parse(response.body)
      end

      private

      def sets_path
        "#{Meta::Api::API_VERSION}/#{Meta::Api.catalog_id}/product_sets"
      end

      def request(verb, path)
        response = connection.public_send(verb, path) do |req|
          req.headers["Accept"] = "application/json"
          req.headers["Authorization"] = "Bearer #{Meta::Api.access_token}"
          yield req
        end
        raise_for_status(response)
        response
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
        raise Meta::Api::TransientError, "meta product_sets request failed: #{error.message}"
      end

      def parse(raw)
        JSON.parse(raw.presence || "{}")
      rescue JSON::ParserError => error
        raise Meta::Api::PermanentError, "unparseable meta body: #{error.message}"
      end
    end
  end
end
