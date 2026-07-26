require "test_helper"

module Meta
  module Api
    class CatalogTest < ActiveSupport::TestCase
      CATALOG_ID = "cat-123".freeze
      URL = "#{Meta::Api::BASE_URL}/#{Meta::Api::API_VERSION}/#{CATALOG_ID}/items_batch".freeze

      REQUESTS = [ { method: "UPDATE", data: { id: "42", title: "Zelda" } } ].freeze

      def with_credentials(&block)
        Meta::Api.stub(:access_token, "test-token") do
          Meta::Api.stub(:catalog_id, CATALOG_ID, &block)
        end
      end

      test "batch POSTs the requests as a PRODUCT_ITEM upsert and returns the body" do
        stub_request(:post, URL).to_return(
          status: 200, body: { "handles" => [ "h1" ] }.to_json, headers: { "Content-Type" => "application/json" }
        )

        body = with_credentials { Meta::Api::Catalog.batch(REQUESTS) }

        assert_equal [ "h1" ], body["handles"]
        assert_requested(:post, URL) do |req|
          payload = JSON.parse(req.body)
          assert_equal "Bearer test-token", req.headers["Authorization"]
          assert_equal "PRODUCT_ITEM", payload["item_type"]
          assert_equal true, payload["allow_upsert"]
          request = payload["requests"].first
          assert_equal "UPDATE", request["method"]
          assert_equal "42", request.dig("data", "id")
          assert_equal "Zelda", request.dig("data", "title")
          true
        end
      end

      test "treats an empty 200 body as an empty hash" do
        stub_request(:post, URL).to_return(status: 200, body: "")
        assert_equal({}, with_credentials { Meta::Api::Catalog.batch(REQUESTS) })
      end

      test "raises PermanentError on an unparseable 200 body" do
        stub_request(:post, URL).to_return(status: 200, body: "not json")
        assert_raises(Meta::Api::PermanentError) { with_credentials { Meta::Api::Catalog.batch(REQUESTS) } }
      end

      test "raises PermanentError on a 4xx carrying a permanent error code" do
        stub_request(:post, URL).to_return(status: 400, body: { "error" => { "code" => 100 } }.to_json)
        assert_raises(Meta::Api::PermanentError) { with_credentials { Meta::Api::Catalog.batch(REQUESTS) } }
      end

      test "raises PermanentError on a 4xx whose body is not JSON" do
        stub_request(:post, URL).to_return(status: 400, body: "<html>bad</html>")
        assert_raises(Meta::Api::PermanentError) { with_credentials { Meta::Api::Catalog.batch(REQUESTS) } }
      end

      test "raises TransientError on a 4xx carrying the batch rate-limit code 80014" do
        stub_request(:post, URL).to_return(status: 400, body: { "error" => { "code" => 80_014 } }.to_json)
        assert_raises(Meta::Api::TransientError) { with_credentials { Meta::Api::Catalog.batch(REQUESTS) } }
      end

      test "raises TransientError on a 429" do
        stub_request(:post, URL).to_return(status: 429, body: "slow down")
        assert_raises(Meta::Api::TransientError) { with_credentials { Meta::Api::Catalog.batch(REQUESTS) } }
      end

      test "raises TransientError on a 5xx" do
        stub_request(:post, URL).to_return(status: 503, body: "down")
        assert_raises(Meta::Api::TransientError) { with_credentials { Meta::Api::Catalog.batch(REQUESTS) } }
      end

      test "raises TransientError on a timeout" do
        stub_request(:post, URL).to_timeout
        assert_raises(Meta::Api::TransientError) { with_credentials { Meta::Api::Catalog.batch(REQUESTS) } }
      end
    end
  end
end
