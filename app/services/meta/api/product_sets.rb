require "faraday"

module Meta
  module Api
    class ProductSets
      include Meta::Api::Client

      EMPTY_SET_SUBCODE = 1_798_130

      def self.list
        new.list
      end

      def self.create(name:, filter:, shop_id:)
        new.create(name: name, filter: filter, shop_id: shop_id)
      end

      def self.update(id, filter:, shop_id:)
        new.update(id, filter: filter, shop_id: shop_id)
      end

      def list
        response = request(:get, sets_path) { |req| req.params["fields"] = "name" }
        parse(response.body).fetch("data", [])
      end

      def create(name:, filter:, shop_id:)
        response = request(:post, sets_path) do |req|
          req.params["name"] = name
          req.params["filter"] = filter.to_json
          req.params["publish_to_shops"] = shops_param(shop_id)
        end
        parse(response.body)
      end

      def update(id, filter:, shop_id:)
        response = request(:post, "#{Meta::Api::API_VERSION}/#{id}") do |req|
          req.params["filter"] = filter.to_json
          req.params["publish_to_shops"] = shops_param(shop_id)
        end
        parse(response.body)
      end

      private

      def shops_param(shop_id)
        [ { shop_id: shop_id } ].to_json
      end

      def sets_path
        "#{Meta::Api::API_VERSION}/#{Meta::Api.catalog_id}/product_sets"
      end

      def request(verb, path)
        response = connection.public_send(verb, path) do |req|
          authorize(req)
          yield req
        end
        raise Meta::Api::EmptyProductSetError, response.body if empty_product_set?(response)
        raise_for_status(response)
        response
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
        raise Meta::Api::TransientError, "meta product_sets request failed: #{error.message}"
      end

      def authorize(req)
        req.headers["Accept"] = "application/json"
        req.headers["Authorization"] = "Bearer #{Meta::Api.access_token}"
      end

      def empty_product_set?(response)
        return false unless response.status == 400

        JSON.parse(response.body.presence || "{}").dig("error", "error_subcode") == EMPTY_SET_SUBCODE
      rescue JSON::ParserError
        false
      end

      def parse(raw)
        JSON.parse(raw.presence || "{}")
      rescue JSON::ParserError => error
        raise Meta::Api::PermanentError, "unparseable meta body: #{error.message}"
      end
    end
  end
end
